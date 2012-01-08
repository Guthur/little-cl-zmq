 ;;;; little-zmq.lisp

(in-package #:zmq-bindings)

#++(declaim (optimize (speed 3)))

(define-condition zmq-error
    (error)
  ((error-number :initarg :error-number
		 :reader error-number))
  (:report (lambda (condition stream)
	      (format stream "An error was raised on a ZMQ funcall.~%")	     
	      (format stream "Error string: ~a~%"
		      (strerror (error-number condition))))))

(defconstant +VERSION-MAJOR+ 3)
(defconstant +VERSION-MINOR+ 1)
(defconstant +VERSION-PATCH+ 1)
(defconstant +VERSION+ (* 3 (+ 10000 1) (+ 100 1)))

;;;Error Numbers

(defmacro define-error-numbers ((hausnumero)
				&body errors)
  `(progn ,@(loop :for error :in errors
		  :collect (list 'defparameter
				 (first error)
				 (+ hausnumero (second error))))))

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

(defmacro kwsym->special (kwsym)
  `(intern (concatenate 'string "+"
			(symbol-name ,kwsym) "+")))

(defmacro find-kwsym-special (kwsym)
  `(find-symbol (concatenate 'string "+"
			     (symbol-name ,kwsym) "+")))

(defmacro define-sequence (&body symbols)
  `(progn
     ,@(loop :for symbol :in symbols
	     :for count :from 0
	     :collect (if (consp symbol)
			  (list 'defparameter
				(kwsym->special (first symbol))
				(setf count (second symbol)))
			  (list 'defparameter
				(kwsym->special symbol)
				count)))))

(defun kwsym-value (kwsym)
  (declare (inline kwsym-value))
  (symbol-value (find-symbol (concatenate 'string "+"
					  (symbol-name kwsym) "+")
			     'zmq-bindings)))

(define-sequence
  :pair
  :pub
  :sub
  :req
  :rep
  :dealer
  :router
  :pull
  :push
  :xpub
  :xsub)


(defmacro make-setter (option-name enum type)
  `(defmethod (setf ,option-name) (value (socket socket))     
     ,(cond
	((eq type :string)
	 `(cffi:with-foreign-string (string value)
	    (setsockopt (slot-value socket 'ptr) ,enum string (length value))))
	(t
	 `(cffi:with-foreign-object (ptr ,type)
	    (setf (cffi:mem-aref ptr ,type) value)
	    (setsockopt (slot-value socket 'ptr) ,enum ptr
			(cffi:foreign-type-size ,type)))))
     value))

(defmacro make-getter (option-name enum type)
  `(defmethod ,option-name
     ((socket socket))
     (cffi:with-foreign-pointer (val ,(if (eq :string type)
					  255
					  (cffi:foreign-type-size type))
				     val-size)
       (cffi:with-foreign-pointer (len ,(cffi:foreign-type-size 'size-t))
	 ,(cond
	    ((eq type :string)
	     `(progn
		(setf (cffi:mem-aref len 'size-t) val-size)
		(getsockopt (slot-value socket 'ptr) ,enum val len)		
		(cffi:foreign-string-to-lisp
		 val :count (cffi:mem-aref len 'size-t))))
	    (t
	     `(progn
		(setf (cffi:mem-aref len :long) val-size
		      (cffi:mem-aref val ,type) 0)
		(getsockopt (slot-value socket 'ptr) ,enum val len)
		(cffi:mem-aref val ,type))))))))

(defmacro define-socket
    (options)
  `(progn
     (defclass socket ()
       ,(append
	 (loop :for option :in options
	       :collect `(,(first option)
			  :accessor ,(first option)))
	 (list '(ptr))))
     ,@(loop :for option :in options
	     :append `(,(when (member :get option)
			  (macroexpand-1 `(make-getter ,(first option)
						       ,(second option)
						       ,(third option))))
		       ,(when (member :set option)
			  (macroexpand-1 `(make-setter ,(first option)
						       ,(second option)
						       ,(third option))))))))

(define-socket
    ((affinity 4 :uint64 :get :set)
     (identity 5 :string :get :set)
     (subscribe 6 :string :set)
     (unsubscribe 7 :string :set)
     (rate 8 :int :get :set)
     (recovery-ivl 9 :int :get :set)
     (sndbuf 11 :int :get :set)
     (rcvbuf 12 :int :get :set)
     (rcvmore 13 :boolean :get)
     (fd 14 :int :get)
     (events 15 :int :get)
     (type 16 :int :get)
     (linger 17 :int :get :set)
     (reconnect-ivl 18 :int :get :set)
     (backlog 19 :int :get :set)
     (reconnect-ivl-max 21 :int :get :set)
     (maxmsgsize 22 :int64 :get :set)
     (sndhwm 23 :int :get :set)
     (rcvhwm 24 :int :get :set)
     (multicast-hops 25 :int :get :set)
     (rcvtimeo 27 :int :get :set)
     (sndtimeo 28 :int :get :set)
     (ipv4only 31 :boolean :get :set)))

(defmethod initialize-instance :before ((socket socket)
					&key skt-ptr type context)
  (if skt-ptr
      (setf (slot-value socket 'ptr) skt-ptr)
      (setf (slot-value socket 'ptr) (socket context type))))

(defun make-socket (ctx type)
  (make-instance 'socket :context ctx :type type))

(defun init-socket (skt-ptr)
  (make-instance 'socket :skt-ptr skt-ptr))

(defun close-socket (skt)
  (close (slot-value skt 'ptr)))

(define-sequence
  (:more 1))

(define-sequence
  (:dontwait 1)
  :sndmore)

(defmacro defcfun* (name-and-options return-type &body args)
  (let* ((c-name (car name-and-options))
         (l-name (cadr name-and-options))
         (n-name (cffi::format-symbol t "%~A" l-name))
         (name (list c-name n-name))
         (docstring (when (stringp (car args)) (pop args)))
         (ret (gensym)))
    (loop :with opt
	  :for i :in args
	  :unless (consp i) :do (setq opt t)
	  :else
	  :collect i :into args*
	  :and :if (not opt) :collect (car i) :into names
	  :else :collect (car i) :into opts
	  :and :collect (list (car i) 0) :into opts-init
	  :end
	  :finally (return
		     `(progn
			(cffi:defcfun ,name ,return-type
			  ,@args*)

			(defun ,l-name (,@names ,@(when opts-init `(&optional ,@opts-init)))
			  ,docstring
			  (let ((,ret (,n-name ,@names ,@opts)))
			    (if ,(if (eq return-type :pointer)
				     `(< (cffi:pointer-address ,ret) 0)
				     `(< ,ret 0))
				(let ((errno (errno)))
				  (error 'zmq-error
					 :error-number errno))
				,ret))))))))

(cffi:defcallback cffi-free-fn :void ((data :pointer) (hint :pointer))
  (declare (ignore hint))
  (print "free")
  #++(cffi:foreign-free data))

(cffi:defcallback cffi-free-string-fn :void ((data :pointer) (hint :pointer))
  (declare (ignore hint))
  (print "free-string")
  #++(cffi:foreign-string-free data))

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

(defcfun* ("zmq_msg_data" msg-data) :pointer
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

(defcfun* ("zmq_sendmsg" sendmsg) :int
  (s :pointer)
  (msg :pointer msg-t)
  (flags :int))

(defcfun* ("zmq_recvmsg" recvmsg) :int
  (s :pointer)
  (msg :pointer msg-t)
  (flags :int))

;;; I/O Multiplexing

(define-sequence
  (:pollin 1)
  (:pollout 2)
  (:pollerr 4))

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

(cffi:defcfun ("alloc_foreign" alloc-foreign) :pointer
  (size size-t))

(cffi:defcfun ("get_free_fn" get-free-fn) :pointer)

