(defpackage #:poll
  (:documentation "Socket Poll API")
  (:use #:common-lisp)
  (:export
   #:poll   
   #:has-events-p
   #:with-poll-list))

(in-package #:poll)

#++(defgeneric set-events (socket poll-item-ptr &rest events))

#++(defmethod set-events ((socket socket:socket) poll-item-ptr &rest events)
     (cffi:with-foreign-slots ((%zmq::socket %zmq::events)
                            poll-item-ptr
                            %zmq::pollitem-t)
    (setf %zmq::socket (slot-value socket 'socket:ptr)
          %zmq::events (+ (if (member :pollin events) %zmq::+pollin+ 0)
                          (if (member :pollout events) %zmq::+pollout+ 0)
                          (if (member :pollerr events) %zmq::+pollerr+ 0)))))

#++(defmethod set-events ((fd t) poll-item-ptr &rest events)
  (cffi:with-foreign-slots ((%zmq::fd %zmq::events)
                            poll-item-ptr
                            %zmq::pollitem-t)
    (setf %zmq::fd fd)
    (setf %zmq::events (+ (if (member :pollin events) %zmq::+pollin+ 0)
                          (if (member :pollout events) %zmq::+pollout+ 0)
                          (if (member :pollerr events) %zmq::+pollerr+ 0)))))


(defun set-events (poll-item)
  (with-slots ((socket socket)
               (events events)
               (poll-item-ptr poll-item-ptr))
      poll-item
    (cffi:with-foreign-slots ((%zmq::socket %zmq::events)
                              poll-item-ptr
                              %zmq::pollitem-t)
      (setf %zmq::socket (slot-value socket 'socket:ptr)
            %zmq::events (+ (if (member :pollin events) %zmq::+pollin+ 0)
                            (if (member :pollout events) %zmq::+pollout+ 0)
                            (if (member :pollerr events) %zmq::+pollerr+ 0)))
      (format t "~a ~a" %zmq::socket %zmq::events))))


(defun has-events-p (poll-item-ptr)
  (cffi:with-foreign-slots ((%zmq::revents) poll-item-ptr %zmq::pollitem-t)
    (values
     (unless (zerop (boole boole-and %zmq::revents %zmq::+pollin+))
       :pollin)
     (unless (zerop (boole boole-and %zmq::revents %zmq::+pollout+))
       :pollout)
     (unless (zerop (boole boole-and %zmq::revents %zmq::+pollin+))
       :pollerr))))

(defclass poll-item ()
  ((socket :initarg :socket
           :reader socket)
   (events :initarg :events)
   (revents :reader revents)
   (poll-item-ptr)))

(defmethod (setf events) (value (poll-item poll-item))
  (with-slots ((events events)
               (poll-item-ptr poll-item-ptr))
      poll-item
    (setf events (alexandria:ensure-list value))
    (when poll-item-ptr
      (set-events poll-item))))

(defun make-poll-item (socket &rest events)
  (make-instance 'poll-item :socket socket :events events))

(defclass poll-list ()
  ((poll-items)
   (poll-array :initform (cffi:foreign-alloc '%zmq::pollitem-t :count 8))
   (poll-count :reader poll-count
               :initform 0)))

(defmethod (setf poll-items) (value (poll-list poll-list))
  (with-slots ((poll-array poll-array)
               (poll-count poll-count)
               (poll-items poll-items))
      poll-list
    (loop
     :for poll-item :in (alexandria:ensure-list value)
     :for index :from 0
     :as poll-item-ptr = (cffi:mem-aref poll-array '%zmq::pollitem-t index)
     :do
     (setf (slot-value poll-item 'poll-item-ptr) poll-item-ptr)
     (set-events poll-item)     
     :finally (setf poll-count (1+ index)))
    (setf poll-items (alexandria:ensure-list value))
    value))

(defmethod initialize-instance :after ((poll-list poll-list) &key poll-items)
  (when poll-items
    (setf (poll-items poll-list) poll-items)))

(defun make-poll-list (&rest poll-items)
  (make-instance 'poll-list :poll-items poll-items))

(defun destroy-poll-list (poll-list)
  (cffi:foreign-free (slot-value poll-list 'poll-array)))


(defun poll (poll-list &optional (timeout -1) (eintr-retry t))
  (with-slots ((poll-items poll-items)
               (poll-array poll-array)
               (poll-count poll-count))
      poll-list
    (loop
     :for item :in poll-items
     :for index :from 0
     :do
     (setf (slot-value item 'revents) nil))
    (let ((evts (%zmq:with-eintr-retry eintr-retry
                  (%zmq::poll poll-array poll-count timeout))))
      (unless (zerop evts)
        (loop
         :for item :in poll-items
         :for index :below poll-count
         :do
         (setf (slot-value item 'revents)
               (has-events-p (cffi:mem-aref poll-array
                                            '%zmq::pollitem-t
                                            index))))
        (values t evts)))))

(defmacro with-poll-list ((poll-list &rest poll-items) &body body)
  `(let ((,poll-list (make-poll-list ,@poll-items)))
     (unwind-protect
          ,@body
       (destroy-poll-list ,poll-list))))
