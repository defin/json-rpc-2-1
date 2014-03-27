(function ($)
 {
     $.jsonrpc = function (options)
     {
         return {
             settings: $.extend({}, $.jsonrpc.defaults, options),
             auth: null,
             id: 0,

             login: function (username, password, loggedInCallback, loginFailedCallback)
             {
                 this.request({'method': 'rpc.login',
                               'params': [username, password],
                               'callback': function (o)
                               {
                                   var info = o[0];
                                   var token = info.shift();
                                   this.auth = token;
                                   if ( $.isFunction(loggedInCallback) )
                                       loggedInCallback(info);
                               },
                               'error': function (o, i, c)
                               {
                                   console.log('ERROR', o, i, c);
                                   if ( $.isFunction(loginFailedCallback) )
                                       loginFailedCallback(c);
                               }
                              });
             },

             logout: function (callback)
             {
                 this.auth = null;
                 this.id = 0;

                 if ( callback )
                     callback();
             },

             request: function (options)
             {
                 if (options === undefined)
                     options = {};

                 var that = this; // uh-oh
                 var callback_fn = options.callback || null;
                 var callback_extra_args = options.callback_extra_args || [];
                 var error_fn = options['error'] || null;
                 var error_extra_args = options.error_extra_args || [];
                 var method = options.method || null;
                 var params = options.params || [];
                 var self = options.self || this;
                 var url = this.settings.url;
                 var rpc = this.makeRequestFrame(method, params);

                 $('body').trigger("rpc.requestBegan", [rpc.id]);

                 console.log('-' + rpc.id + '- RPC request: ' + rpc.method + '(' + rpc.params + ')');

                 var ajax_failed = function (what)
                 {
                     // what to do for network errors
                     $('body').trigger("rpc.requestEnded", [rpc.id]);
                     console.log('-' + rpc.id + '- RPC network failed: ', what);
                 };

                 var ajax_succeeded = function (o)
                 {
                     $('body').trigger("rpc.requestEnded", [rpc.id]);
                     console.log('-' + o.id + '- RPC response: ', o.result || o.error);
                     if ('error' in o)
                     {
                         if ($.isFunction(error_fn))
                         {
                             var err = [o.error.code, o.error.data, o.error.message].concat(error_extra_args);
                             if ( o.error._backtrace !== null )
                                 console.log('BACKTRACE:', o.error._backtrace);
                             error_fn.apply(self, err);
                         }
                     } else if ('result' in o)
                     {
                         if ($.isFunction(callback_fn))
                         {
                             var r = [o.result].concat(callback_extra_args);
                             callback_fn.apply(self, r);
                         }
                     } else {
                        // and what if it doesn't? call an event handler for a custom event?
                     }
                 };

                 $.ajax({
                          'cache': false,
                          'contentType': 'application/json; charset=utf-8',
                          'crossdomain': false,
                          'data': JSON.stringify(rpc), //jsonParse(rpc) to undo
                          'dataType': 'json',
                          'error': function (o) { ajax_failed.apply(that, [o]); },
                          'success': function (o) { ajax_succeeded.apply(that, [o]); },
                          'type': 'POST',
                          'url': this.settings.url
                        });
             },

             makeRequestFrame: function (method, params)
             {
                 this.id += 1;

                 var frame =
                     {
                         'id': this.id,
                         'method': method,
                         'params': params,
                         'auth': this.auth,
                         'jsonrpc': '2.1'
                     };

                 return frame;
             }
         };
     };

     $.jsonrpc.destroy = function ()
     {
         delete $.jsonrpc;
     };

     $.jsonrpc.defaults =
         {
             'url': 'https://localhost/json-rpc/',
             'crossdomain': false
         };
 })(jQuery);
