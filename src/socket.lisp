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
   #:connect
   #:disconnect
   #:subscribe))

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
               :collect `(,(caar option)))
         (list '(ptr))))
     ,@(loop :for option :in options
             :append
             (let* ((name (caar option))
                    (option-values (cdar option))
                    (doc (cdr option))
                    (id (getf option-values :id))
                    (type (getf option-values :type))
                    (protocol (alexandria:ensure-list
                               (getf option-values :protocol '(:get :set :init)))))
               `(,(when (member :get protocol)
                    (macroexpand-1 `(make-getter ,name ,id ,type ,doc)))
                 ,(when (member :set protocol)
                    (macroexpand-1 `(make-setter ,name ,id ,type ,doc))))))
     (defmethod initialize-instance
         ((socket socket)
          &key
            bind connect
            ,@(loop :for option :in options
                    :append
                    (let* ((name (caar option))
                           (option-values (cdar option))
                           (type (getf option-values :type))
                           (protocol (alexandria:ensure-list
                                      (getf option-values :protocol
                                            '(:get :set :init)))))
                      (when (member :init protocol)
                        (if (eq :boolean type)
                            (list `(,name :default))
                            (list name))))))
       ,@(loop :for option :in options
               :append
               (let* ((name (caar option))
                      (option-values (cdar option))
                      (type (getf option-values :type))
                      (protocol (alexandria:ensure-list
                                 (getf option-values :protocol
                                       '(:get :set :init)))))
                 (when (member :init protocol)
                   (list (if (eq :boolean type)
                             `(unless (eq ,name :default)
                                (setf (,name socket) ,name))
                             `(when ,name
                                (setf (,name socket) ,name)))))))
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
    (((affinity :id 4
                :type :uint64)
      :documentation "ZMQ_AFFINITY socket option.")
     ((identity :id 5
                :type :binary)
      :documentation "ZMQ_IDENTITY socket option.")
     ((subscribe :id 6
                 :type :binary
                 :protocol :set)
      :documentation "ZMQ_SUBSCRIBE socket option.")
     ((unsubscribe :id 6
                   :type :binary
                   :protocol :set)
      :documentation "ZMQ_UNSUBSCRIBE socket option.")
     ((rate :id 8
            :type :int)
      :documentation "ZMQ_RATE socket option.")
     ((recovery-ivl :id 9
                    :type :int)
      :documentation "ZMQ_RECOVERY socket option.")
     ((sndbuf :id 11
              :type :int)
      :documentation "ZMQ_SNDBUF socket option.")
     ((rcvbuf :id 12
              :type :int)
      :documentation "ZMQ_RCVBUF socket option.")
     ((rcvmore :id 13
               :type :boolean
               :protocol :get)
      :documentation "ZMQ_RCVMORE socket option.")
     ((fd :id 14
          :type :int
          :protocol :get)
      :documentation "ZMQ_FD socket option.")
     ((events :id 15
              :type :int
              :protocol :get)
      :documentation "ZMQ_EVENTS socket option.")
     ((type :id 16
            :type :int
            :protocol :get)
      :documentation "ZMQ_TYPE socket option.")
     ((linger :id 17
              :type :int
              :protocol (:get :set))
      :documentation "ZMQ_LINGER socket option.")
     ((reconnect-ivl :id 18
                     :type :int)
      :documentation "ZMQ_RECONNECT-IVL socket option.")
     ((backlog :id 19
               :type :int)
      :documentation "ZMQ_BACKLOG socket option.")
     ((reconnect-ivl-max :id 21
                         :type :int)
      :documentation "ZMQ_RECONNECT-IVL_MAX socket option.")
     ((maxmsgsize :id 22
                  :type :int64)
      :documentation "ZMQ_MAXMSGSIZE socket option.")
     ((sndhwm :id 23
              :type :int)
      :documentation "ZMQ_SNDHWM socket option.")
     ((rcvhwm :id 24
              :type :int)
      :documentation "ZMQ_RCVHWM socket option.")
     ((multicast-hops :id 25
                      :type :int)
      :documentation "ZMQ_MULTICAST-HOPS socket option.")
     ((rcvtimeo :id 27
                :type :int)
      :documentation "ZMQ_RCVTIMEO socket option.")
     ((sndtimeo :id 28
                :type :int)
      :documentation "ZMQ_SNDTIMEO socket option.")
     ((ipv4only :id 31
                :type :boolean)
      :documentation "ZMQ_IPV4ONLY socket option.")
     ((last-endpoint :id 32
                     :type :binary
                     :protocol :get)
      :documentation "ZMQ_LAST_ENDPOINT: Retrieve the last endpoint set")
     ((fail-unroutable :id 33
                       :type :boolean
                       :protocol (:set :init))
      :documentation "ZMQ_FAIL_UNROUTABLE: Set unroutable message behavior")
     ((tcp-keepalive :id 34
                     :type :int)
      :documentation "ZMQ_TCP_KEEPALIVE: Override SO_KEEPALIVE socket option")
     ((tcp-keepalive-idle :id 35
                          :type :int)
      :documentation "ZMQ_TCP_KEEPALIVE_IDLE: Override TCP_KEEPCNT(or TCP_KEEPALIVE on some OS)")
     ((tcp-keepalive-cnt :id 36
                         :type :int)
      :documentation "ZMQ_TCP_KEEPALIVE_CNT: Override TCP_KEEPCNT socket option")
     ((tcp-keepalive-intvl :id 37
                           :type :int)
      :documentation "ZMQ_TCP_KEEPALIVE_INTVL: Override TCP_KEEPINTVL socket option")
     ((tcp-accept-filter :id 38
                         :type :binary
                         :protocol (:set :init))
      :documentation "ZMQ_TCP_ACCEPT_FILTER: Assign filters to allow new TCP connections")))


(defmethod (setf subscribe) ((value cons) (socket socket))
  (dolist (sub value)
    (setf (subscribe socket) sub))
  value)

(defmethod (setf unsubscribe) ((value cons) (socket socket))
  (dolist (unsub value)
    (setf (unsubscribe socket) unsub))
  value)


(defmethod (setf tcp-keepalive) :before (value (socket socket))
  (assert (<= -1 value 1) nil
          "Incorrect option value - Socket option tcp-keepalive takes values -1, 0, 1"))

(defmethod (setf tcp-keepalive-idle) :before (value (socket socket))
  (assert (and (<= -1 value) (not (zerop value))) nil
          "Incorrect option value - Socket option tcp-keepalive-idle takes values -1, >0"))

(defmethod (setf tcp-keepalive-cnt) :before (value (socket socket))
  (assert (and (<= -1 value) (not (zerop value))) nil
          "Incorrect option value - Socket option tcp-keepalive-cnt takes values -1, >0"))

(defmethod (setf tcp-keepalive-intvl) :before (value (socket socket))
  (assert (and (<= -1 value) (not (zerop value))) nil
          "Incorrect option value - Socket option tcp-keepalive-intvl takes values -1, >0"))

(defmethod (setf fail-unroutable) :before (value (socket socket))
  (assert (eq (class-of socket) (find-class 'router)) nil
          "Incorrect socket type - Socket option fail-unroutable is only applicable to ROUTER sockets"))

(defmethod initialize-instance :before ((socket socket)
                                        &key type context)
  (setf (slot-value socket 'ptr) (%zmq::socket (context:ptr context) type)))

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
                  (change-class (make-zmq-socket ctx
                                                 ,(second socket-pair)
                                                 parameters)
                                ',(intern (symbol-name (first socket-pair)))))))
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
  (when (keywordp type)
    (unless (find-method #'make-socket nil `(,(find-class t) (eql ,type)) nil)
      (error (format nil "Incorrect socket type specified (~s)~%" type))))
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

(defun disconnect (socket address)
  (declare (cl:type string address)
           (cl:type socket socket))
  (%zmq::disconnect (slot-value socket '%zmq::ptr) address))