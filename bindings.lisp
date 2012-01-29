 ;;;; little-zmq.lisp

(in-package #:zmq-bindings)

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

(defconstant +VERSION-MAJOR+ 3)
(defconstant +VERSION-MINOR+ 1)
(defconstant +VERSION-PATCH+ 1)
(defconstant +VERSION+ (* 3 (+ 10000 1) (+ 100 1)))

;;;Error Numbers

(defmacro define-error-numbers ((hausnumero)
				&body errors)
  (declare (cl:type fixnum hausnumero))
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

(defmacro make-setter (option-name enum type)
  `(progn
     (defgeneric (setf ,option-name) (value socket))
     ,@(cond
	((eq type :binary)	
	 `((defmethod (setf ,option-name) ((value string) (socket socket))
	     (cffi:with-foreign-string (string value)
	       (setsockopt (slot-value socket 'ptr) ,enum string (length value)))
	     value)
	   (defmethod (setf ,option-name) ((value vector) (socket socket))
	     (declare (cl:type (vector (unsigned-byte 8) *) value))
	     (cffi:with-foreign-object (ptr :char (length value))
	       (loop :for octet :across value
		     :for index :from 0
		     :do
			(setf (cffi:mem-aref ptr :char index) octet))
	       (setsockopt (slot-value socket 'ptr) ,enum ptr (length value)))
	     value)))
	(t
	 `((defmethod (setf ,option-name) (value (socket socket))
	     (cffi:with-foreign-object (ptr ,type)
	       (setf (cffi:mem-aref ptr ,type) value)
	       (setsockopt (slot-value socket 'ptr) ,enum ptr
			   (cffi:foreign-type-size ,type)))
	     value))))))


(defmacro make-getter (option-name enum type)
  `(progn
     ,@(cond
	 ((eq :binary type)
	  `((defgeneric ,option-name (socket &key as))
	    (defmethod ,option-name ((socket socket) &key (as :octets))
	      (cffi:with-foreign-pointer (val 255 val-size)
		(cffi:with-foreign-pointer (len ,(cffi:foreign-type-size
						  'size-t))
		  (setf (cffi:mem-aref len 'size-t) val-size)
		  (getsockopt (slot-value socket 'ptr) ,enum val len)
		  (let ((count (cffi:mem-aref len 'size-t)))
		    (ecase as
		      (:octets
		       (make-array count
				   :element-type '(unsigned-byte 8)
				   :initial-contents
				   (loop :for index :from 0 :below count
					 :collect
					 (cffi:mem-aref val :char index))))
		      (:string
		       (cffi:foreign-string-to-lisp val :count count)))))))))
	 (t
	  `((defgeneric ,option-name (socket))
	    (defmethod ,option-name ((socket socket))
	      (cffi:with-foreign-pointer (val ,(cffi:foreign-type-size type)
					      val-size)
		(cffi:with-foreign-pointer (len ,(cffi:foreign-type-size
						  'size-t))
		  (setf (cffi:mem-aref len 'size-t) val-size)
		  (getsockopt (slot-value socket 'ptr) ,enum val len)
		  (setf (cffi:mem-aref len :long) val-size
			(cffi:mem-aref val ,type) 0)
		  (getsockopt (slot-value socket 'ptr) ,enum val len)
		  (cffi:mem-aref val ,type)))))))))

(defmacro define-socket
    (options)
  `(progn
     (defclass socket ()
       ,(append
	 (loop :for option :in options
	       :collect `(,(first option)))
	 (list '(ptr))))
     ,@(loop :for option :in options
	     :append `(,(when (member :get option)
			  (macroexpand-1 `(make-getter ,(first option)
						       ,(second option)
						       ,(third option))))
		       ,(when (member :set option)
			  (macroexpand-1 `(make-setter ,(first option)
						       ,(second option)
						       ,(third option))))))
     (defmethod initialize-instance
	 ((socket socket)
	  &key
	    bind connect
	    ,@(loop :for option :in options
		    :append (when (member :init option)
			      (if (eq :boolean (third option))
				  (list `(,(first option) :default))
				  (list (first option))))))
       ,@(loop :for option :in options
	       :append (when (member :init option)
			 (list (if (eq :boolean (third option))
				   `(unless (eq ,(first option) :default)
				      (setf (,(first option) socket)
					    ,(first option)))
				   `(when ,(first option)
				      (setf (,(first option) socket)
					    ,(first option)))))))
       (with-slots ((ptr ptr))
	   socket
	 (when bind
	   (mapcar (lambda (addr)
		     (bind ptr addr))
		   (alexandria:ensure-list bind)))
	 (when connect
	   (mapcar (lambda (addr)
		     (connect ptr addr))
		   (alexandria:ensure-list connect)))))))

(define-socket
    ((affinity 4 :uint64 :get :set :init)
     (identity 5 :binary :get :set :init)
     (subscribe 6 :binary :set)
     (unsubscribe 7 :binary :set)
     (rate 8 :int :get :set :init)
     (recovery-ivl 9 :int :get :set :init)
     (sndbuf 11 :int :get :set :init)
     (rcvbuf 12 :int :get :set :init)
     (rcvmore 13 :boolean :get)
     (fd 14 :int :get)
     (events 15 :int :get)
     (type 16 :int :get)
     (linger 17 :int :get :set)
     (reconnect-ivl 18 :int :get :set :init)
     (backlog 19 :int :get :set :init)
     (reconnect-ivl-max 21 :int :get :set :init)
     (maxmsgsize 22 :int64 :get :set :init)
     (sndhwm 23 :int :get :set :init)
     (rcvhwm 24 :int :get :set :init)
     (multicast-hops 25 :int :get :set :init)
     (rcvtimeo 27 :int :get :set :init)
     (sndtimeo 28 :int :get :set :init)
     (ipv4only 31 :boolean :get :set :init)))


(defmethod (setf subscribe) ((value cons) (socket socket))
  (dolist (sub value)
    (setf (subscribe socket) sub))
  value)

(defmethod (setf unsubscribe) ((value cons) (socket socket))
  (dolist (unsub value)
    (setf (unsubscribe socket) unsub))
  value)

(defmethod initialize-instance :before ((socket socket)
					&key type context)
  (setf (slot-value socket 'ptr) (socket context type)))

(defmethod initialize-instance :after ((socket socket)
				       &key subscribe linger)
  (when linger
    (setf (linger socket) linger))
  (when subscribe
    (setf (subscribe socket) subscribe)))


(defun make-zmq-socket (ctx type parameters)
  (apply 'make-instance 'socket :context ctx :type type parameters))


(defmacro define-socket-types (socket-name-constant-pairs)
  `(progn
     (defgeneric make-socket (context type &rest parameters))
     ,@(loop :for socket-pair :in socket-name-constant-pairs
	     :collect
	     `(defmethod make-socket (ctx (type (eql ,(first socket-pair)))
				      &rest parameters)
		(declare (inline make-zmq-socket))
		(change-class (make-zmq-socket ctx
					       ,(second socket-pair)
					       parameters)
			      (quote
			       ,(intern (symbol-name (first socket-pair)))))))
     ,@(loop :for socket-pair :in socket-name-constant-pairs
	     :collect
	     `(defclass ,(intern (symbol-name (first socket-pair))) (socket)
		()))))

(define-socket-types
    ((:pair 0)
     (:pub 1)
     (:sub 2)
     (:req 3)
     (:rep 4)
     (:dealer 5)
     (:router 6)
     (:pull 7)
     (:push 8)
     (:xpub 9)
     (:xsub 10)))


(defun close-socket (skt)
  (close (slot-value skt 'ptr)))

(defparameter +more+ 1)

(defparameter +dontwait+ 1)
(defparameter +sndmore+ 2)

#++(defmacro defcfun* (name-and-options return-type &body args)
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

			(defun ,l-name (,@names ,@(when opts-init
						    `(&optional ,@opts-init)))
			  ,docstring
			  (let ((,ret (,n-name ,@names ,@opts)))
			    (if ,(if (eq return-type :pointer)
				     `(< (cffi:pointer-address ,ret) 0)
				     `(< ,ret 0))
				(let ((errno (errno)))
				  (error 'zmq-error
					 :error-number errno))
				,ret))))))))

(defmacro defcfun* (name-and-options return-type &body args)
  (let* ((lisp-name (cadr name-and-options))
	 (foreign-name (car name-and-options))
	 (binding-lisp-name (concatenate 'string "%" (symbol-name lisp-name))))
    `(progn
       (cffi:defcfun (,foreign-name ,(intern binding-lisp-name)) ,return-type
	 ,@args)
       (defun ,lisp-name ,(loop :for arg :in args
				:collect (car arg))
	 (declare (inline ,lisp-name))
	 (let ((ret (,(intern binding-lisp-name)
		     ,@(loop :for arg :in args
			     :collect (car arg)))))
	   ,(when (eq return-type :int)
	      '(declare (cl:type fixnum ret)))
	   (when ,(if (eq return-type :pointer)
		      '(cffi:null-pointer-p ret)
		      '(< ret 0))
	     (cond
	       ((= +eintr+ (errno))
		(signal 'zmq-eintr))
	       (t (error 'zmq-error
			 :error-number (errno)))))
	   ret)))))

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

(defcfun* ("zmq_sendmsg" sendmsg) :int
  (s :pointer)
  (msg :pointer msg-t)
  (flags :int))

(defcfun* ("zmq_recvmsg" recvmsg) :int
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
