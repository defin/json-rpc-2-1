(defpackage :json-rpc
  (:use :common-lisp)
  (:export #:handle-rpc #:define-rpc-method #:define-rpc-package-translation
           #:invalid-credentials #:not-logged-in #:invalid-auth-token #:auth-token-expired #:insufficient-access
           #:invalid-method #:invalid-parameters #:invalid-frame #:internal-error #:rpc-exception #:log-rpc))

(defpackage :json-rpc-auth
  (:use :common-lisp :json-rpc)
  (:export #:auth-level #:auth-username #:decode-auth-token #:has-access-for-method?))

(in-package :json-rpc)

(define-condition rpc-exception (error)
  ((message :initarg :message :reader rpc-exception-message)
   (code :initarg :code :reader rpc-exception-code)
   (data :initarg :data :reader rpc-exception-data :initform nil)))

(define-condition invalid-credentials (rpc-exception)
  ((message :initform "Username and/or password invalid")
   (code :initform "InvalidCredentials")))

(define-condition not-logged-in (rpc-exception)
  ((message :initform "Not logged in or session expired")
   (code :initform "NotLoggedIn")))

(define-condition insufficient-access (rpc-exception)
  ((message :initform "Insufficient access for operation")
   (code :initform "InsufficientAccess")))

(define-condition invalid-method (rpc-exception)
  ((message :initform "Invalid method name")
   (code :initform "InvalidMethod")))

(define-condition invalid-parameters (rpc-exception)
  ((message :initform "Invalid parameters to method")
   (code :initform "InvalidParameters")))

(define-condition invalid-frame (error)
  ((message :initform "Invalid JSON-RPC 2.1 frame")
   (code :initform "InvalidFrame")
   (problem :initarg :problem)))

(define-condition internal-error (rpc-exception)
  ((message :initform "Internal error while processing request")
   (code :initform "InternalError")
   (internal-exception :initarg :internal-exception :reader internal-error-internal-exception)))

(define-condition invalid-auth-token (not-logged-in)
  ((message :initform "Invalid Auth Token")
   (code :initform "InvalidAuth")))

(define-condition auth-token-expired (not-logged-in)
  ((message :initform "Auth Token Expired")
   (code :initform "ExpiredAuth")))

(defstruct (rpc) method params auth id headers)

(defun handle-rpc (frame &optional headers)
  (let (rpc)
    (handler-case
        (setq rpc (deframe-request frame))
      (invalid-frame (e)
        "Bad or missing JSON-RPC 2.1 frame"))
    (handler-case
        (progn
          (setf (rpc-headers rpc) headers)
          (unless (eq (rpc-auth rpc) :null)
            (setf (rpc-auth rpc) (json-rpc-auth:decode-auth-token (rpc-auth rpc))))
          (make-response-frame rpc (rpc-apply rpc)))
      (rpc-exception (e)
        (make-error-response-frame rpc e))
      (error (e)
        (make-error-response-frame rpc (make-instance 'internal-error :internal-exception e))))))

(defmethod rpc-apply ((rpc rpc))
  (let* ((method (get-rpc-method (rpc-method rpc))))
    (if (check-access-level method (rpc-auth rpc))
        (multiple-value-list (apply (symbol-function method) rpc (rpc-params rpc)))
        (error 'insufficient-access))))

(defun check-access-level (rpc-method-symbol auth)
  (let ((method-auth-level (get rpc-method-symbol :json-rpc)))
    (if (or (null method-auth-level)
            (json-rpc-auth:has-access-for-method? (json-rpc-auth:auth-level auth)
                                                  (symbol-name method-auth-level)))
        t)))

(defun deframe-request (frame)
  (let ((req (handler-case
                 (st-json:read-json frame nil)
               (error (e)
                 (error 'invalid-frame :problem "Invalid JSON document")))))
    (flet ((find-key (key error)
             (multiple-value-bind (value foundp)
                 (st-json:getjso key req)
               (if foundp
                   value
                   (error 'invalid-frame :problem error)))))
      (let* ((method (find-key "method" "No method"))
             (params (find-key "params" "No params"))
             (auth (find-key "auth" "No auth"))
             (id (find-key "id" "No id")))
        ;; validate fields of o conform to spec
        (unless (string= (find-key "jsonrpc" "No JSON-RPC version") "2.1")
          (error 'invalid-frame :problem "Wrong JSON-RPC version"))
        (unless (integerp id)
          (error 'invalid-frame :problem "Wrong type of id"))
        (unless (or (eq auth :null) (stringp auth))
          (error 'invalid-frame :problem "Invalid auth"))
        (make-rpc :method method :params params :auth auth :id id)))))

(defmethod make-response-frame ((rpc rpc) (result t))
  (st-json:write-json-to-string
   (st-json:jso "id" (rpc-id rpc)
                "result" result
                "jsonrpc" "2.1")))

(defmethod make-error-response-frame-internal ((id integer) (error-response rpc-exception))
  (with-slots (message code data) error-response
      (let ((backtrace (if (typep error-response 'internal-error)
                           (trivial-backtrace:print-backtrace
                            (internal-error-internal-exception error-response) :output nil)
                           nil)))
        (st-json:write-json-to-string
         (st-json:jso "id" id
                      "error" (st-json:jso "code" code
                                           "message" message
                                           "data" (or data :null)
                                           "_backtrace" (or backtrace :null))
                      "jsonrpc" "2.1")))))

(defmethod make-error-response-frame ((rpc rpc) (error-response rpc-exception))
  (make-error-response-frame-internal (rpc-id rpc) error-response))

(defmethod make-error-response-frame ((rpc null) (error-response rpc-exception))
  (make-error-response-frame-internal 0 error-response))

#|
In the lisp implementation of JSON-RPC 2.1, the first N-1 dots of the
method name are part of the package name and whatever is after the
last dot is the symbol name.  There is a lookup table mapping rpc
package names to lisp package names.  Mappings must be defined for the
RPC method name to resolve.

RPC methods must be exported from their respective packages to be
accessible, and must have a :json-rpc property on the symbol, with the
value being a keyword denoting authorization level the method
requires, or nil for none.
|#

(defvar *package-lookup-table* (make-hash-table :test 'string-equal))

(defun define-rpc-package-translation (rpc-name lisp-name)
  (setf (gethash rpc-name *package-lookup-table*) lisp-name))

(defun find-rpc-package (package-name)
  (let ((translated (gethash package-name *package-lookup-table* nil)))
    (if translated
        (find-package translated)
        nil)))

(defun get-rpc-method (name)
  (let* ((last-dot (position #\. name :from-end t))
         (package (or (find-rpc-package (string-upcase (subseq name 0 last-dot)))
                      (error 'invalid-method :data name)))
         (method (or (find-symbol (subseq name (1+ last-dot)) package) ; need to upcase when not in modern mode!  blah!
                     (error 'invalid-method :data name)))
         (not-found (gensym))
         (json-rpc (get method :json-rpc not-found)))
    (if (eq json-rpc not-found)
        (error 'invalid-method :data name)
        method)))

(defmacro define-rpc-method ((name authorization-level) (&rest args) &body body)
  (let ((self (intern "self"))) ;  make this symbol visible in package calling macro
    `(progn
       (defun ,name (,self ,@args) ,@body)
       (setf (get ',name :json-rpc) ,authorization-level)
       ',name)))
