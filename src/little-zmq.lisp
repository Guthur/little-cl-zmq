(defpackage #:little-zmq
  (:documentation "Public API for little-zmq ZeroMQ Common Lisp Binding")
  (:use #:cl
        #:message
        #:poll
        #:socket)
  (:nicknames #:zmq)
  (:shadowing-import-from #:socket
                          #:push
                          #:identity)
  (:import-from #:%zmq
                #:version
                #:eagain
                #:error-number)
  (:import-from #:context
		#:with-context)
  (:export #:with-context
           #:with-eintr-retry
           #:sendmsg
           #:recvmsg
           #:rcvmore
           #:dealer
           #:router
           #:pub
           #:sub
           #:push
           #:pull
           #:pair
           #:req
           #:rep
           #:with-poll-list
           #:with-message
           #:poll
           #:has-events-p
           #:with-socket
           #:with-sockets
           #:size
           #:msg-t
           #:msg-t-ptr
           #:version
           #:subscribe
           #:data
           #:string-message
           #:error-number
           #:eagain))

(in-package #:little-zmq)

(declaim (optimize (speed 3)))

#++(defmacro with-context ((ctx &optional (io-threads 1)) &body body)
  `(let ((,ctx (%zmq::init ,io-threads)))
     (unwind-protect
          (progn
            ,@body)
       (%zmq::term ,ctx))))

(declaim (inline sendmsg))
(defgeneric sendmsg (socket data &key eintr-retry send-more))

(defmethod sendmsg (socket (data cons)
                    &key (eintr-retry t) send-more)
  (declare (type (cons (or message
                           string
                           (simple-array (unsigned-byte 8) (*)))
                       (or cons
                           null)) data)
           (type (boolean) eintr-retry)
           (type socket socket))
  (labels ((send (msg-list)
             (cond
               ((null (cdr msg-list))
                (sendmsg socket (car msg-list) :eintr-retry eintr-retry
                                               :send-more send-more))
               (t
                (sendmsg socket (car msg-list) :eintr-retry eintr-retry
                                               :send-more t)
                (send (cdr msg-list))))))
    (send data)))

(defmethod sendmsg (socket (data (eql nil))
                    &key (send-more nil) (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry)
           (type socket socket))
  (with-message (msg)
    (sendmsg socket msg :eintr-retry eintr-retry :send-more send-more)))

(defmethod sendmsg (socket (data vector)
                    &key (send-more nil) (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry)
           (type socket socket)
           (type (simple-array (unsigned-byte 8) (*)) data))
  (with-message (msg data)
    (sendmsg socket msg :send-more send-more :eintr-retry eintr-retry)))

(defmethod sendmsg (socket (data string)
                    &key (send-more nil) (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry)
           (type socket socket)
           (type string data))
  (with-message (msg data)
    (sendmsg socket msg :send-more send-more :eintr-retry eintr-retry)))

(defmethod sendmsg (socket (data message)
                    &key send-more (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry)
           (type socket socket)
           (type message data))
  (%zmq::sendmsg (slot-value socket 'ptr)
                 (msg-t-ptr data)
                 (if send-more %zmq::+sndmore+ 0)
                 eintr-retry))

(defmethod sendmsg (socket (data function)
                    &key (send-more nil) (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry)
           (type socket socket)
           (type (function (message &optional (or null symbol))
                           (values t t)) data))
  (with-message (msg)
    (multiple-value-bind (msg more)
        (funcall data msg)
      (if more
          (progn
            (sendmsg socket msg :send-more t :eintr-retry eintr-retry)
            (sendmsg socket data :send-more send-more :eintr-retry eintr-retry))
          (sendmsg socket msg :send-more send-more :eintr-retry eintr-retry)))))

(declaim (inline recvmsg))
(defgeneric recvmsg (socket message &key blocking as eintr-retry))

(defmethod recvmsg (socket (message message)
                    &key (blocking t) as (eintr-retry t))
  (declare (type (boolean) eintr-retry blocking)
           (type message message)
           (type (or null symbol) as)
           (type socket socket))
  (%zmq::recvmsg (slot-value socket 'ptr)
                 (msg-t-ptr message)
                 (if blocking 0 %zmq::+dontwait+)
                 eintr-retry)
  (when as (change-class message as))
  message)

(defmethod recvmsg (socket (message (eql :string))
                    &key (blocking t) as (eintr-retry t))
  (declare (ignore as)
           (type socket socket))
  (with-message (msg)
    (data (recvmsg socket msg :as 'string-message
                              :blocking blocking
                              :eintr-retry eintr-retry))))

(defmethod recvmsg (socket (message (eql :octet))
                    &key (blocking t) as (eintr-retry t))
  (declare (ignore as)
           (type socket socket))
  (with-message (msg)
    (data (recvmsg socket msg :as 'octet-message
                              :blocking blocking
                              :eintr-retry eintr-retry))))



(defun make-message-future (socket &key (blocking t) (eintr-retry t))
  (let ((more t))
    (lambda (msg &key as)
      (if more
          (progn
            (recvmsg socket msg :as as
                                :blocking blocking
                                :eintr-retry eintr-retry)
            (setf more (rcvmore socket))
            (values msg more))
          (values nil nil)))))

(defmacro with-message-future ((sym socket
                                &key (blocking t) (eintr-retry t))
                               &body body)
  (alexandria:with-gensyms (more)
    `(let ((,more t))
       (flet ((,sym (msg &key as)
                (if ,more
                    (progn
                      (let ((res (recvmsg ,socket msg
                                          :as as
                                          :blocking ,blocking
                                          :eintr-retry ,eintr-retry)))
                        (setf ,more (rcvmore ,socket))
                        (values res ,more)))
                    (values nil nil))))
         (progn
           ,@body)))))