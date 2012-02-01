 ;;;; little-zmq.lisp

(defpackage #:zmq-bindings
  (:documentation "Low level binding to ZeroMQ C API")
  (:nicknames #:%zmq)
  (:use #:common-lisp #:zmq-bindings-grovel)
  (:shadow #:close)
  (:export
   #:with-eintr-retry))

(in-package #:zmq-bindings)

(cffi:define-foreign-library zeromq
  (:darwin (:or "libzmq.3.dylib" "libzmq.dylib"))
  (:unix (:or "libzmq.so.3" "libzmq.so"))
  (:windows "libzmq.dll")
  (t "libzmq"))

(cffi:use-foreign-library zeromq)

(declaim (optimize (speed 3)))

(define-condition zmq-error
    (error)
  ((error-number :initarg :error-number
		 :reader error-number))
  (:report (lambda (condition stream)
	     (declare (cl:type stream stream))
	      (format stream "An error was raised on a ZMQ funcall.~%")
	      (format stream "Error string: ~a~%"
		      (strerror (error-number condition))))))

;;; EINTR Retry

(defun call-with-retry (predicate thunk)
  (declare (inline call-with-retry)
	   (type (function nil) thunk)
	   (type (function (error) boolean) predicate))
  (tagbody retry
     (return-from call-with-retry
       (handler-bind ((t (lambda (condition)			   
                           (when (funcall predicate condition)
                             (go retry)))))
         (funcall thunk)))))

(defmacro with-eintr-retry (&optional (active t) &body body)
  `(if ,active
       (call-with-retry
	(lambda (condition)
	  (and (typep condition '%zmq::zmq-error)
	       (eql (%zmq::error-number condition)
		    %zmq::+eintr+)))
	(lambda ()
	  ,@body))
       (progn
	 ,@body)))


;;;Error Numbers

(defmacro define-error-numbers ((hausnumero)
				&body errors)
  (declare (cl:type fixnum hausnumero))
  `(progn ,@(loop :for (symbol number) (symbol fixnum) :in errors
		  :collect (list 'defparameter
				 symbol
				 (+ hausnumero number)))))

(define-error-numbers (156384712)
  (+enotsup+ 1)
  (+eprotonosupport+ 2)
  (+enobufs+ 3)
  (+enetdown+ 4)
  (+eaddrinuse+ 5)
  (+eaddrnotavail+ 6)
  (+econnrefused+ 7)
  (+einprogress+ 8)
  (+enotsock+ 9)
  (+eafnosupport+ 10)
  (+efsm+ 51)
  (+enocompatproto+ 52)
  (+eterm+ 53)
  (+emthread+ 54))

(defparameter +more+ 1)

(defparameter +dontwait+ 1)
(defparameter +sndmore+ 2)


(defmacro defcfun* (name-and-options return-type &body args)
  (let* ((lisp-name (cadr name-and-options))
	 (foreign-name (car name-and-options))
	 (binding-lisp-name (concatenate 'string "%" (symbol-name lisp-name))))
    `(progn
       (cffi:defcfun (,foreign-name ,(intern binding-lisp-name)) ,return-type
	 ,@args)
       (declaim (inline ,lisp-name))
       (defun ,lisp-name ,(loop :for arg :in args
				:collect (car arg))
	 (let ((ret (,(intern binding-lisp-name)
		      ,@(loop :for arg :in args
			      :collect (car arg)))))
	   ,(when (or (eq return-type :int)
		      (eq return-type 'size-t))
	      '(declare (cl:type fixnum ret)))
	   (when ,(if (eq return-type :pointer)
		      '(cffi:null-pointer-p ret)
		      '(< ret 0))
	     (error 'zmq-error
		    :error-number (errno)))
	   ret)))))

(defmacro defcfun+ (name-and-options return-type &body args)
  (let* ((lisp-name (cadr name-and-options))
	 (foreign-name (car name-and-options))
	 (binding-lisp-name (concatenate 'string "%" (symbol-name lisp-name))))
    `(progn
       (cffi:defcfun (,foreign-name ,(intern binding-lisp-name)) ,return-type
	 ,@args)       
       (defun ,lisp-name ,(append (loop :for arg :in args
					:collect (car arg))
			   '(&optional eintr-retry))
	 (let ((ret 0))
	   (declare (type fixnum ret))
	   (tagbody
	    retry
	      (setf ret (,(intern binding-lisp-name)
			 ,@(loop :for arg :in args
				 :collect (car arg))))	      
	      (when ,(if (eq return-type :pointer)
			 '(cffi:null-pointer-p ret)
			 '(< ret 0))
		(let ((err (errno)))
		  (declare (type fixnum err))
		  (if (and eintr-retry (= +eintr+ err))
		      (go retry)
		      (error 'zmq-error :error-number err)))))
	   ret)))))

(defun version ()
  (cffi:with-foreign-objects ((major :int)
			      (minor :int)
			      (patch :int))
    (zmq_version major minor patch)
    (values (cffi:mem-aref major :int)
	    (cffi:mem-aref minor :int)
	    (cffi:mem-aref patch :int))))

(cffi:defcfun ("zmq_version" zmq_version) :void
  (major :pointer :int)
  (minor :pointer :int)
  (patch :pointer :int))

(cffi:defcfun ("zmq_errno" errno) :int)

(cffi:defcfun ("zmq_strerror" strerror) :string
  (errnum :int))

;;; ZMQ Message definition

(cffi:defcstruct (msg-t :size 32))

(defcfun* ("zmq_msg_init" msg-init) :int
  (msg :pointer msg-t))

(defcfun* ("zmq_msg_init_size" msg-init-size) :int
  (msg :pointer msg-t)
  (size size-t))

(defcfun* ("zmq_msg_init_data" msg-init-data) :int
  (msg :pointer msg-t)
  (data :pointer)
  (size size-t)
  (ffn :pointer)
  (hint :pointer))

(defcfun* ("zmq_msg_close" msg-close) :int
  (msg :pointer msg-t))

(defcfun* ("zmq_msg_move" msg-move) :int
  (dest :pointer msg-t)
  (src :pointer msg-t))

(defcfun* ("zmq_msg_copy" msg-copy) :int
  (dest :pointer msg-t)
  (src :pointer msg-t))

(cffi:defcfun ("zmq_msg_data" msg-data) :pointer
  (msg :pointer msg-t))

(defcfun* ("zmq_msg_size" msg-size) size-t
  (msg :pointer msg-t))

(defcfun* ("zmq_getmsgopt" getmsgopt) :int
  (msg :pointer msg-t)
  (option :int)
  (optval :pointer)
  (optvallen :pointer))

;;; ZMQ infrastructure

(defcfun* ("zmq_init" init) :pointer
  (io_threads :int))

(defcfun* ("zmq_term" term) :int
  (context :pointer))

;;; ZMQ Socket Definition

(defcfun* ("zmq_socket" socket) :pointer
  (context :pointer)
  (type :int))

(defcfun* ("zmq_close" close) :int
  (s :pointer))

(defcfun* ("zmq_setsockopt" setsockopt) :int
  (s :pointer)
  (option :int)
  (optval :pointer)
  (optvallen :long))

(defcfun* ("zmq_getsockopt" getsockopt) :int
  (s :pointer)
  (option :int)
  (optval :pointer)
  (optvallen :pointer))

(defcfun* ("zmq_bind" bind) :int
  (s :pointer)
  (addr :string))

(defcfun* ("zmq_connect" connect) :int
  (s :pointer)
  (addr :string))

(defcfun* ("zmq_send" send) :int
  (s :pointer)
  (buf :pointer)
  (len :pointer)
  (flags :int))

(defcfun* ("zmq_recv" recv) :int
  (s :pointer)
  (buf :pointer)
  (len :pointer)
  (flags :int))

(defcfun+ ("zmq_sendmsg" sendmsg) :int
  (s :pointer)
  (msg :pointer msg-t)
  (flags :int))

(defcfun+ ("zmq_recvmsg" recvmsg) :int
  (s :pointer)
  (msg :pointer msg-t)
  (flags :int))

;;; I/O Multiplexing


(defparameter +pollin+ 1)
(defparameter +pollout+ 2)
(defparameter +pollerr+ 4)

(cffi:defcstruct pollitem-t
	(socket :pointer)
	(fd :int)
	(events :short)
	(revents :short))

(defcfun* ("zmq_poll" poll) :int
  (items :pointer pollitem-t)
  (nitems :int)
  (timeout :long))

;;; MISC functions

(cffi:defcfun ("memcpy" memcpy) :pointer
  (dst :pointer)
  (src :pointer)
  (len size-t))


