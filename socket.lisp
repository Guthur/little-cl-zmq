(defpackage #:socket
  (:documentation "Socket API")
  (:use #:common-lisp)
  (:shadow #:type #:identity #:push)
  (:export
   #:ptr
   #:socket
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
   #:xsub
   #:with-socket
   #:with-sockets
   #:bind
   #:connect))

(in-package #:socket)

(declaim (optimize (speed 3)))

(defmacro make-setter (option-name enum type doc)
  `(progn
     (defgeneric (setf ,option-name) (value socket)
	,doc)
      ,@(cond
	  ((eq type :binary)	
	   `((defmethod (setf ,option-name) ((value string) (socket socket))
	       (cffi:with-foreign-string (string value)
		 (%zmq::setsockopt (slot-value socket 'ptr) ,enum string
				  (length value)))
	       value)
	     (defmethod (setf ,option-name) ((value vector) (socket socket))
	       (declare (cl:type (simple-array (unsigned-byte 8) (*)) value))
	       (cffi:with-foreign-object (ptr :char (length value))
		 (loop :for octet :across value
		       :for index :from 0
		       :do
		       (setf (cffi:mem-aref ptr :char index) octet))
		 (%zmq::setsockopt (slot-value socket 'ptr) ,enum ptr
				   (length value)))
	       value)))
	  (t
	   `((defmethod (setf ,option-name) (value (socket socket))
	       (cffi:with-foreign-object (ptr ,type)
		 (setf (cffi:mem-aref ptr ,type) value)
		 (%zmq::setsockopt (slot-value socket 'ptr) ,enum ptr
				  (cffi:foreign-type-size ,type)))
	       value))))))


 (defmacro make-getter (option-name enum type doc)
   `(progn
      ,@(cond
	  ((eq :binary type)
	   `((defgeneric ,option-name (socket &key as)
	       ,doc)
	     (defmethod ,option-name ((socket socket) &key (as :octets))
	       (cffi:with-foreign-pointer (val 255 val-size)
		 (cffi:with-foreign-pointer (len ,(cffi:foreign-type-size
						   '%zmq::size-t))
		  (setf (cffi:mem-aref len '%zmq::size-t) val-size)
		  (%zmq::getsockopt (slot-value socket 'ptr) ,enum val len)
		  (let ((count (cffi:mem-aref len '%zmq::size-t)))
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
	  `((defgeneric ,option-name (socket)
	      ,doc)
	    (defmethod ,option-name ((socket socket))
	      (cffi:with-foreign-pointer (val ,(cffi:foreign-type-size type)
					      val-size)
		(cffi:with-foreign-pointer (len ,(cffi:foreign-type-size
						  '%zmq::size-t))
		  (setf (cffi:mem-aref len '%zmq::size-t) val-size
			(cffi:mem-aref val ,type) 0)
		  (%zmq::getsockopt (slot-value socket 'ptr) ,enum val len)
		  (cffi:mem-aref val ,type)))))))))

(defmacro define-socket (options)
  `(progn
     (defclass socket ()
       ,(append
	 (loop :for option :in options
	       :collect `(,(first (car option))))
	 (list '(ptr))))
     ,@(loop :for option :in options
	     :append
	     (let ((parameters (car option))
		   (doc (cdr option)))
	       `(,(when (member :get parameters)
		    (macroexpand-1 `(make-getter ,(first parameters)
						 ,(second parameters)
						 ,(third parameters)
						 ,doc)))
		 ,(when (member :set parameters)
		    (macroexpand-1 `(make-setter ,(first parameters)
						 ,(second parameters)
						 ,(third parameters)
						 ,doc))))))
     (defmethod initialize-instance
	 ((socket socket)
	  &key
	    bind connect
	    ,@(loop :for option :in options
		    :append (when (member :init (car option))
			      (if (eq :boolean (third (car option)))
				  (list `(,(first (car option)) :default))
				  (list (first (car option)))))))
       ,@(loop :for option :in options
	       :append (when (member :init (car option))
			 (list (if (eq :boolean (third (car option)))
				   `(unless (eq ,(first (car option)) :default)
				      (setf (,(first (car option)) socket)
					    ,(first (car option))))
				   `(when ,(first (car option))
				      (setf (,(first (car option)) socket)
					    ,(first (car option))))))))
       (with-slots ((ptr ptr))
	   socket
	 (when bind
	   (mapcar (lambda (addr)
		     (%zmq::bind ptr addr))
		   (alexandria:ensure-list bind)))
	 (when connect
	   (mapcar (lambda (addr)
		     (%zmq::connect ptr addr))
		   (alexandria:ensure-list connect)))))))

(define-socket
    (((affinity 4 :uint64 :get :set :init)
      :documentation "ZMQ_AFFINITY socket option.")
     ((identity 5 :binary :get :set :init)
      :documentation "ZMQ_IDENTITY socket option.")
     ((subscribe 6 :binary :set)
      :documentation "ZMQ_SUBSCRIBE socket option.")
     ((unsubscribe 7 :binary :set)
      :documentation "ZMQ_UNSUBSCRIBE socket option.")
     ((rate 8 :int :get :set :init)
      :documentation "ZMQ_RATE socket option.")
     ((recovery-ivl 9 :int :get :set :init)
      :documentation "ZMQ_RECOVERY socket option.")
     ((sndbuf 11 :int :get :set :init)
      :documentation "ZMQ_SNDBUF socket option.")
     ((rcvbuf 12 :int :get :set :init)
      :documentation "ZMQ_RCVBUF socket option.")
     ((rcvmore 13 :boolean :get)
      :documentation "ZMQ_RCVMORE socket option.")
     ((fd 14 :int :get)
      :documentation "ZMQ_FD socket option.")
     ((events 15 :int :get)
      :documentation "ZMQ_EVENTS socket option.")
     ((type 16 :int :get)
      :documentation "ZMQ_TYPE socket option.")
     ((linger 17 :int :get :set)
      :documentation "ZMQ_LINGER socket option.")
     ((reconnect-ivl 18 :int :get :set :init)
      :documentation "ZMQ_RECONNECT-IVL socket option.")
     ((backlog 19 :int :get :set :init)
      :documentation "ZMQ_BACKLOG socket option.")
     ((reconnect-ivl-max 21 :int :get :set :init)
      :documentation "ZMQ_RECONNECT-IVL_MAX socket option.")
     ((maxmsgsize 22 :int64 :get :set :init)
      :documentation "ZMQ_MAXMSGSIZE socket option.")
     ((sndhwm 23 :int :get :set :init)
      :documentation "ZMQ_SNDHWM socket option.")
     ((rcvhwm 24 :int :get :set :init)
      :documentation "ZMQ_RCVHWM socket option.")
     ((multicast-hops 25 :int :get :set :init)
      :documentation "ZMQ_MULTICAST-HOPS socket option.")
     ((rcvtimeo 27 :int :get :set :init)
      :documentation "ZMQ_RCVTIMEO socket option.")
     ((sndtimeo 28 :int :get :set :init)
      :documentation "ZMQ_SNDTIMEO socket option.")
     ((ipv4only 31 :boolean :get :set :init)
      :documentation "ZMQ_IPV4ONLY socket option.")))


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
  (setf (slot-value socket 'ptr) (%zmq::socket context type)))

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
	     (let ((socket-pair (car socket-pair)))
	       `(defmethod make-socket (ctx (type (eql ,(first socket-pair)))
					&rest parameters)
		  (declare (inline make-zmq-socket))
		  (change-class (make-zmq-socket ctx
						 ,(second socket-pair)
						 parameters)
				(quote
				 ,(intern (symbol-name (first socket-pair))))))))     
     ,@(loop :for socket-pair :in socket-name-constant-pairs
	     :collect
	     (let ((doc (cdr socket-pair))
		   (socket-pair (car socket-pair)))
	       `(defclass ,(intern (symbol-name (first socket-pair))) (socket)
		  ()
		  ,doc)))))

(define-socket-types
    (((:pair 0)
      :documentation "Class: pair
Class precedence: socket
ZMQ API Reference: http://api.zeromq.org/3-1:zmq-socket#toc17")
     ((:pub 1)
      :documentation "Class: pub
Class precedence: socket
ZMQ API Reference: http://api.zeromq.org/3-1:zmq-socket#toc9")
     ((:sub 2)
      :documentation "Class: sub
Class precedence: socket
ZMQ API Reference: http://api.zeromq.org/3-1:zmq-socket#toc10")
     ((:req 3)
      :documentation "Class: req
Class precedence: socket
ZMQ API Reference: http://api.zeromq.org/3-1:zmq-socket#toc4")
     ((:rep 4)
      :documentation "Class: rep
Class precedence: socket
ZMQ API Reference: http://api.zeromq.org/3-1:zmq-socket#toc5")
     ((:dealer 5)
      :documentation "Class: dealer
Class precedence: socket
ZMQ API Reference: http://api.zeromq.org/3-1:zmq-socket#toc6")
     ((:router 6)
      :documentation "Class: router
Class precedence: socket
ZMQ API Reference: http://api.zeromq.org/3-1:zmq-socket#toc7")
     ((:pull 7)
      :documentation "Class: pull
Class precedence: socket
ZMQ API Reference: http://api.zeromq.org/3-1:zmq-socket#toc15")
     ((:push 8)
      :documentation "Class: push
Class precedence: socket
ZMQ API Reference: http://api.zeromq.org/3-1:zmq-socket#toc14")
     ((:xpub 9)
      :documentation "Class: xpub
Class precedence: socket
ZMQ API Reference: http://api.zeromq.org/3-1:zmq-socket#toc11")
     ((:xsub 10)
           :documentation "Class: xsub
Class precedence: socket
ZMQ API Reference: http://api.zeromq.org/3-1:zmq-socket#toc12")))


(defun close-socket (skt)
  (%zmq::close (slot-value skt 'ptr)))


(defmacro with-socket ((socket context type &rest parameters)
		       &body body)
  `(let ((,socket (make-socket ,context ,type ,@parameters)))
     (unwind-protect
	  (progn
	    ,@body)
       (close-socket ,socket))))

(defmacro with-sockets (socket-list &body body)
  (if socket-list
      `(with-socket ,(car socket-list)
	 (with-sockets ,(cdr socket-list)
	   ,@body))
      `(progn ,@body)))

(defun bind (socket address)
  (declare (cl:type string address)
	   (cl:type socket socket))
  (%zmq::bind (slot-value socket '%zmq::ptr) address))

(defun connect (socket address)
  (declare (cl:type string address)
	   (cl:type socket socket))
  (%zmq::connect (slot-value socket '%zmq::ptr) address))

