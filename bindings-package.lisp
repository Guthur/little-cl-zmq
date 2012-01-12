(defpackage #:zmq-bindings
  (:nicknames #:%zmq)
  (:use #:common-lisp)
  (:shadow #:close #:type #:identity)
  (:export
   #:init
   #:term
   #:make-socket
   #:kwsym-value
   #:close-socket
   #:setsockopt
   #:getsockopt
   #:sendmsg
   #:recvmsg
   #:send
   #:recv
   #:affinity
   #:identity
   #:subscribe
   #:unsubscribe
   #:rate
   #:recovery-ivl
   #:sndbuf
   #:rcvbuf
   #:rcvmore
   #:fd
   #:events
   #:type
   #:linger
   #:reconnect-ivl
   #:backlog
   #:reconnect-ivl-max
   #:maxmsgsize
   #:sndhwm
   #:rcvhwm
   #:multicast-hops
   #:rcvtimeo
   #:sndtimeo
   #:msg-init
   #:msg-init-size
   #:msg-init-data
   #:msg-close
   #:msg-move
   #:msg-copy
   #:msg-data
   #:msg-size))

(in-package #:zmq-bindings)

(cffi:define-foreign-library zeromq
  (:darwin (:or "libzmq.3.dylib" "libzmq.dylib"))
  (:unix (:or "libzmq.so.3" "libzmq.so"))
  (:windows "libzmq.dll")
  (t "libzmq"))

(cffi:use-foreign-library zeromq)
