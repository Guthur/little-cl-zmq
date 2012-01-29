;;;; package.lisp

(defpackage #:little-zmq
  (:use #:cl)
  (:nicknames #:zmq)
  (:import-from #:%zmq
		#:rcvmore
		#:pair 
		#:pub 
		#:sub
		#:req
		#:rep
		#:dealer
		#:router
		#:pull
		#:xpub
		#:xsub)
  (:shadowing-import-from #:%zmq #:push #:identity)
  (:export
   #:with-context
   #:with-socket
   #:with-sockets
   #:with-message
   #:with-message-future
   #:make-message-future
   #:with-poll-list
   #:with-eintr-retry
   #:sendmsg
   #:recvmsg
   #:rcvmore
   #:data
   #:poll
   #:has-events-p
   #:make-message
   #:close-message
   #:free-message
   #:destroy-message
   #:octet-message
   #:string-message
   #:as-string-message
   #:as-octet-message
   #:binary-address-to-string
   #:message
   #:pair 
   #:pub 
   #:sub
   #:req
   #:rep
   #:dealer
   #:router
   #:push
   #:pull
   #:xpub
   #:xsub
   #:has-more-p))

