import sys

class RPCException (Exception):
    def __init__(self, message, apiMessage, code, data=None):
        self.message = message
        self.apiMessage = apiMessage
        self.code = code
        self.data = data

class NotLoggedInException (RPCException):
    def __init__ (self, message=None):
        RPCException.__init__(self, message, "You must be logged in to perform this action.", 'NotLoggedIn', None)

class InvalidCredentialsException (RPCException):
    def __init__ (self, message=None):
        RPCException.__init__(self, message, 'Invalid username and/or password', 'BadAuth', None)

class InsufficientAccessException (RPCException):
    def __init__ (self, method=None):
        RPCException.__init__(self, method, 'Insufficient access to call method "%s"' % method, 'BadACL', None)

class SystemUnavailableException (RPCException):
    def __init__ (self, message=None):
        RPCException.__init__(self, message, 'System unavailable, please try again later', 'SystemUnavailable', None)


class ServiceException(RPCException):
    pass

class ServiceMethodNotTranslatableException(ServiceException):
    def __init__ (self, method):
        RPCException.__init__(self, method, 'Error translating service method "%s"' % method, 'RequestNotTranslatable', None)

class ServiceMethodInvalidArgumentsException(ServiceException):
    def __init__(self, method):
        RPCException.__init__(self, method, 'Invalid arguments given to service method "%s"' % method, 'InvalidArguments', None)

class ServiceMethodInsufficientAccessException (RPCException):
    def __init__ (self, method):
        RPCException.__init__(self, method, 'Insufficient access level to call service method "%s"' % method, 'SystemUnavailable', None)




class JSONEncodeException(Exception):
    def __init__(self, obj):
        self.obj = obj

    def __str__(self):
        return "Cannot JSON encode object: %s" % self.obj

class JSONDecodeException(Exception):
    def __init__(self, message):
        self.message = message

    def __str__(self):
        return self.message

