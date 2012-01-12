;;;; package.lisp

(defpackage #:little-zmq
  (:use #:cl)
  (:nicknames #:zmq)
  (:export
   #:with-context
   #:with-socket
   #:with-sockets
   #:sendmsg
   #:recvmsg
   #:recvall
   #:with-polls
   #:data
   #:exit-poll
   #:bypass-poll
   #:make-message
   #:make-octet-message
   #:make-string-message
   #:octet-message
   #:string-message
   #:message))

