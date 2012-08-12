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
           #:send-message
           #:receive-message
           #:receive-all
           #:bind
           #:connect
           #:disconnect
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
           #:octet-message
           #:error-number
           #:eagain
           #:bind
           #:connect
           #:disconnect
           #:make-poll-item
           #:events
           #:poll-items
           #:revents))

(in-package #:little-zmq)

(declaim (optimize (speed 3)))

(declaim (inline send-message))
(defgeneric send-message (socket data &key eintr-retry send-more))

(defmethod send-message (socket (data cons)
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
                (send-message socket (car msg-list) :eintr-retry eintr-retry
                                                    :send-more send-more))
               (t
                (send-message socket (car msg-list) :eintr-retry eintr-retry
                                                    :send-more t)
                (send (cdr msg-list))))))
    (send data)))

(defmethod send-message (socket (data (eql nil))
                         &key (send-more nil) (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry)
           (type socket socket))
  (with-message (msg)
    (send-message socket msg :eintr-retry eintr-retry :send-more send-more)))

(defmethod send-message (socket (data vector)
                         &key (send-more nil) (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry)
           (type socket socket)
           (type (simple-array (unsigned-byte 8) (*)) data))
  (with-message (msg data)
    (send-message socket msg :send-more send-more :eintr-retry eintr-retry)))

(defmethod send-message (socket (data string)
                         &key (send-more nil) (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry)
           (type socket socket)
           (type string data))
  (with-message (msg data)
    (send-message socket msg :send-more send-more :eintr-retry eintr-retry)))

(defmethod send-message (socket (data message)
                         &key send-more (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry)
           (type socket socket)
           (type message data))
  (%zmq::sendmsg (slot-value socket 'ptr)
                 (msg-t-ptr data)
                 (if send-more %zmq::+sndmore+ 0)
                 eintr-retry))

(defmethod send-message (socket (data function)
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
            (send-message socket msg :send-more t
                                     :eintr-retry eintr-retry)
            (send-message socket data :send-more send-more
                                      :eintr-retry eintr-retry))
          (send-message socket msg :send-more send-more
                                   :eintr-retry eintr-retry)))))

(declaim (inline receive-message))
(defgeneric receive-message (socket message &key blocking eintr-retry))

(defmethod receive-message (socket (message message)
                            &key (blocking t) (eintr-retry t))
  (declare (type (boolean) eintr-retry blocking)
           (type message message)
           (type socket socket))
  (let ((length (%zmq::recvmsg (slot-value socket 'ptr)
                               (msg-t-ptr message)
                               (if blocking 0 %zmq::+dontwait+)
                               eintr-retry)))
    (values message length)))



(defmethod receive-message (socket (message (eql :string))
                            &key (blocking t) (eintr-retry t))
  (declare (type socket socket))
  (with-message (msg)
    (receive-message socket msg :blocking blocking
                                :eintr-retry eintr-retry)
    (data (change-class msg 'string-message))))

(defmethod receive-message (socket (message (eql :octet))
                            &key (blocking t) (eintr-retry t))
  (declare (type socket socket))
  (with-message (msg)
    (receive-message socket msg :blocking blocking
                                :eintr-retry eintr-retry)
    (data (change-class msg 'octet-message))))

(declaim (inline receive-all))
(defgeneric receive-all (socket type &key blocking eintr-retry))

(defmethod receive-all (socket (type (eql :string))
                        &key (blocking t) (eintr-retry t))
  (with-message (msg)
    (change-class msg 'string-message)
    (loop
      :collect (data (receive-message socket msg
                                      :blocking blocking
                                      :eintr-retry eintr-retry))
      :while (zmq:rcvmore socket))))

(defmethod receive-all (socket (type (eql :octet))
                        &key (blocking t) (eintr-retry t))
  (with-message (msg)
    (change-class msg 'octet-message)
    (loop
      :collect (data (receive-message socket msg
                                      :blocking blocking
                                      :eintr-retry eintr-retry))
      :while (zmq:rcvmore socket))))

(defun make-message-future (socket &key (blocking t) (eintr-retry t))
  (let ((more t))
    (lambda (msg)
      (if more
          (progn
            (receive-message socket msg :blocking blocking
                                        :eintr-retry eintr-retry)
            (setf more (rcvmore socket))
            (values msg more))
          (values nil nil)))))

(defmacro with-message-future ((sym socket
                                &key (blocking t) (eintr-retry t))
                               &body body)
  (alexandria:with-gensyms (more)
    `(let ((,more t))
       (flet ((,sym (msg)
                (if ,more
                    (progn
                      (let ((res (receive-message ,socket msg
                                                  :blocking ,blocking
                                                  :eintr-retry ,eintr-retry)))
                        (setf ,more (rcvmore ,socket))
                        (values res ,more)))
                    (values nil nil))))
         (progn
           ,@body)))))