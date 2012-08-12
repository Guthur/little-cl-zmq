(defpackage #:poll
  (:documentation "Socket Poll API")
  (:use #:common-lisp)
  (:export
   #:poll   
   #:has-events-p
   #:with-poll-list
   #:make-poll-item
   #:events
   #:revents
   #:poll-items))

(in-package #:poll)

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
                            (if (member :pollerr events) %zmq::+pollerr+ 0))))))


(defun has-events-p (poll-item-ptr)
  (cffi:with-foreign-slots ((%zmq::revents) poll-item-ptr %zmq::pollitem-t)
    (loop
      :for zmq-event :in (list %zmq::+pollin+ %zmq::+pollout+ %zmq::+pollerr+)
      :for revent :in '(:pollin :pollout :pollerr)
      :unless (zerop (boole boole-and %zmq::revents zmq-event))
        :collect revent)))

(defclass poll-item ()
  ((socket :initarg :socket
           :reader socket)
   (events :initarg :events
           :accessor events)
   (revents :reader revents
            :initform nil)
   (poll-item-ptr)))

(defmethod (setf events) (value (poll-item poll-item))
  (with-slots ((events events)
               (poll-item-ptr poll-item-ptr))
      poll-item
    (setf events (alexandria:ensure-list value))
    (when poll-item-ptr
      (set-events poll-item))))

(defun reset-revents (poll-item)
  (setf (slot-value poll-item 'revents) nil))

(defun make-poll-item (socket &rest events)
  (make-instance 'poll-item :socket socket :events events))

(defclass poll-list ()
  ((poll-items :accessor poll-items)
   (poll-array-size :initform 8)
   (poll-array)
   (poll-count :reader poll-count
               :initform 0)))

(defmethod (setf poll-items) (value (poll-list poll-list))
  (with-slots ((poll-array poll-array)
               (poll-count poll-count)
               (poll-array-size poll-array-size)
               (poll-items poll-items))
      poll-list
    (let ((value (alexandria:ensure-list value)))
      (when (> (length value) poll-array-size)
        (cffi:foreign-free poll-array)
        (setf poll-array-size (* poll-array-size 2)
              poll-array (cffi:foreign-alloc '%zmq::pollitem-t
                                             :count poll-array-size)))
      (loop
        :for poll-item :in value
        :for index :from 0
        :as poll-item-ptr = (cffi:mem-aref poll-array '%zmq::pollitem-t index)
        :do
           (setf (slot-value poll-item 'poll-item-ptr) poll-item-ptr)
           (set-events poll-item)     
        :finally (setf poll-count (1+ index)))
      (setf poll-items value))))

(defmethod initialize-instance :after ((poll-list poll-list) &key poll-items)
  (setf (slot-value poll-list 'poll-array)
        (cffi:foreign-alloc '%zmq::pollitem-t
                            :count (slot-value poll-list 'poll-array-size)))
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
      :do
         (setf (cffi:foreign-slot-value (slot-value item 'poll-item-ptr)
                                        '%zmq::pollitem-t
                                        '%zmq::revents)
               0
               (slot-value item 'revents) nil))
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
          (progn
            ,@body)
       (destroy-poll-list ,poll-list))))
