;;; THIS FILE IS A TEMPLATE
;;; Skeleton of how to plug JSON-RPC 2.0 into an auth provider
;;; Copy and fill in the blanks for a specific auth environment

(in-package :json-rpc-auth)

;; auth-level needs to take an unpacked auth token and determine somehow what access level it authorizes.
(defun auth-level (auth)
  )

;; needs to take a packed auth token and decode it to some internal form
(defun decode-auth-token (token)
  token)

(define-rpc-package-translation "rpc" :json-rpc-auth)

(define-rpc-method (login nil) (username password)
  ;; do something to log in
  ;; do something to make an auth token representing logged-in user
  )

(define-rpc-method (logout nil) ()
  )

(define-rpc-method (loggedIn nil) ()
  )

(define-rpc-method (accessLevel nil) ()
  )

