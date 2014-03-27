import sys
import inspect
import traceback
import json
import types

from auth import auth
import rpc.exceptions

DEBUG = True

class RPCServer (object):
    def __init__(self, service):
        self.requestID = -1
        self.debug = DEBUG
        self.apiPathNodes = {}
        self.authToken = None
        self.moduleMap = {}

    def handleRequest(self, frame):
        result = None
        (requestMethod, requestArgs, requestToken, self.requestID, requestDebug) \
            = self.deframeRequest(frame)
        self.authToken = auth.AuthToken(requestToken)
        try:
            if requestDebug == True and type(requestToken) is types.NoneType:
                if self.hasAccess(requestToken, 'Super'):
                    self.debug = True

            method = self.locateServiceEndpoint(requestMethod)
            print 'FOUND METHOD: {}'.format(method)
            if self.hasAccess(requestToken, method.aclLevel):
                result = self.invokeServiceEndpoint(method, requestArgs)
                return self.frameResponse(result)
        except Exception as e:
            return self.frameErrorResponse(e)

    def deframeRequest(self, frame):
        try:
            message = json.loads(frame)
        except Exception as e:
            raise rpc.exceptions.JSONDecodeException("Failed to deserialize JSON"), None, sys.exc_info()[2]

        # required keys

        if 'jsonrpc' in message \
            and message['jsonrpc'] == '2.0s':
            pass
        else:
            raise rpc.exceptions.JSONDecodeException("Invalid JSON-RPC 2.0s message: unsupported RPC version")

        if 'method' in message:
            requestMethod = message['method']
        else:
            raise rpc.exceptions.JSONDecodeException("Invalid JSON-RPC 2.0s message: missing method")

        if 'params' in message:
            requestArgs = message['params']
        else:
            raise rpc.exceptions.JSONDecodeException("Invalid JSON-RPC 2.0s message: missing parameters")

        if 'id' in message:
            requestID = message['id']
        else:
            raise rpc.exceptions.JSONDecodeException("Invalid JSON-RPC 2.0s message: missing ID")

        # not neccessarily required keys

        requestToken = message['auth'] if 'auth' in message else None
        if requestToken == '':
            requestToken = None
        requestDebug = True if 'debug' in message else False

        return (requestMethod, requestArgs, requestToken, requestID, requestDebug)

    def hasAccess(self, token, aclLevel):
        if aclLevel == 'None':
            return True
        if type(token) is types.NoneType:
            raise rpc.exceptions.NotLoggedInException()
        try:
            if auth.checkACL(token, aclLevel):
                return True
            else:
                cn = self.authToken.getUsername()
                raise rpc.exceptions.InsufficientAccessException(method)
        except auth.AuthTokenException as e:
            raise rpc.exceptions.RPCException(e.message, 'Invalid Authorization, re-log in', 'BadAuthToken'), None, sys.exc_info()[2]
        except Exception as k:
            raise rpc.exceptions.SystemUnavailableException(k.message), None, sys.exc_info()[2]

    def locateServiceEndpoint(self, requestMethod):
        parts = requestMethod.split(".")
        baseModuleName = self.moduleMap[parts[0]] if parts[0] in self.moduleMap else parts[0]
        moduleName = baseModuleName + ".api"
        methodName = parts[1]

        if moduleName not in sys.modules:
            try:
                module = __import__(moduleName)
                serviceProvider = module.api.Service(self.authToken)
            except Exception as e:
                raise rpc.exceptions.ServiceMethodNotTranslatableException(requestMethod), None, sys.exc_info()[2]
        else:
           module = sys.modules[moduleName]
           serviceProvider = module.Service(self.authToken)

        self.apiPathNodes[moduleName] = serviceProvider

        try:
            method = getattr(serviceProvider, methodName)
        except Exception as e:
            raise rpc.exceptions.ServiceMethodNotTranslatableException(requestMethod), None, sys.exc_info()[2]

        if getattr(method, "IsServiceMethod"):
            return method
        else:
            raise rpc.exceptions.ServiceMethodNotTranslatableException(requestMethod)


    def invokeServiceEndpoint(self, meth, args):
        neededLen = len(inspect.getargspec(meth).args) -1

        if isinstance(args, list):
            if neededLen != len(args):
                raise rpc.exceptions.ServiceMethodInvalidArgumentsException(meth.__name__)
            else:
                return meth(*args)
        elif isinstance(args, dict):
            if neededLen != len(args):
                raise rpc.exceptions.ServiceMethodInvalidArgumentsException(meth.__name__)
            else:
                return meth(**args)
        else:
            raise Exception("Invalid arguments")

    def frameResponse(self, retval):
        try:
            print 'RETVAL: %s' % (repr(retval))
            return json.dumps({'result': retval,
                                'id': self.requestID,
                                'jsonrpc': '2.0s' })
        except Exception as e:
            raise rpc.exceptions.JSONEncodeException('Error Processing Request'), None, sys.exc_info()[2]

    def frameErrorResponse(self, error, id=None):
        try:
            rpcid = self.requestID if id == None else id
            details = {}

            if isinstance(error, rpc.exceptions.RPCException):
                details['message'] = error.apiMessage
                details['code'] = error.code
                details['data'] = error.data
            else:
                details['message'] = "Error Processing Request"
                details['code'] = 'FAIL'
                details['data'] = None

            if self.debug:
                details['_message'] = error.message
                details['_class'] = error.__class__.__name__
                details['_stack'] = traceback.format_tb(sys.exc_info()[2])
                details['_file'] = None
                details['_line'] = None
                if hasattr(error, 'methodName'):
                    details['_methodName'] = error.methodName

            return json.dumps({ 'id': rpcid,
                                'jsonrpc': '2.1',
                                'error': details })
        except Exception as e:
            raise rpc.exceptions.JSONEncodeException('Error Processing Request'), None, sys.exc_info()[2]
