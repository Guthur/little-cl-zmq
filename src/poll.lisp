(defpackage #:poll
  (:documentation "Socket Poll API")
  (:use #:common-lisp #:socket)
  (:export
   #:poll   
   #:has-events-p
   #:with-poll-list))

(in-package #:poll)

(defgeneric set-events (socket poll-item-ptr &rest events))

(defmethod set-events ((socket socket) poll-item-ptr &rest events)
  (cffi:with-foreign-slots ((%zmq::socket %zmq::events)
			    poll-item-ptr
			    %zmq::pollitem-t)
    (setf socket (slot-value socket '%zmq::ptr)
	  %zmq::events (+ (if (member :pollin events) %zmq::+pollin+ 0)
			  (if (member :pollout events) %zmq::+pollout+ 0)
			  (if (member :pollerr events) %zmq::+pollerr+ 0)))))

(defmethod set-events ((fd t) poll-item-ptr &rest events)
  (cffi:with-foreign-slots ((%zmq::fd %zmq::events)
			    poll-item-ptr
			    %zmq::pollitem-t)
    (setf %zmq::fd fd)
    (setf %zmq::events (+ (if (member :pollin events) %zmq::+pollin+ 0)
			  (if (member :pollout events) %zmq::+pollout+ 0)
			  (if (member :pollerr events) %zmq::+pollerr+ 0)))))


(defun has-events-p (poll-item-ptr)
  (cffi:with-foreign-slots ((%zmq::revents) poll-item-ptr %zmq::pollitem-t)
    (values
     (unless (zerop (boole boole-and %zmq::revents %zmq::+pollin+))
       :pollin)
     (unless (zerop (boole boole-and %zmq::revents %zmq::+pollout+))
       :pollout)
     (unless (zerop (boole boole-and %zmq::revents %zmq::+pollin+))
       :pollerr))))

(defclass poll-list ()
  ((poll-items
    :initarg :poll-items
    :reader poll-items)
   (poll-count
    :initarg :poll-count
    :reader poll-count)))

(defun poll (poll-list &optional (timeout -1) (eintr-retry t))
  (let ((evts (%zmq:with-eintr-retry eintr-retry
		  (%zmq::poll (poll-items poll-list)
			      (poll-count poll-list)
			      timeout))))
    (unless (zerop evts)
      (values evts))))

(defmacro with-poll-list ((symbol &rest poll-items) &body body)
  (alexandria:with-gensyms (poll-array)
    `(cffi:with-foreign-object
	 (,poll-array '%zmq::pollitem-t ,(length poll-items))
       (let ((,symbol (make-instance 'poll-list
				     :poll-items ,poll-array
				     :poll-count ,(length poll-items)))
	     ,@(loop :for item :in poll-items
		     :for index :from 0
		     :collect `(,(first item)
				(cffi:mem-aref ,poll-array
					       '%zmq::pollitem-t
					       ,index))))
	 ,@(loop :for item :in poll-items
		 :for index :from 0
		 :collect `(set-events ,(second item)
				       (cffi:mem-aref ,poll-array
						      '%zmq::pollitem-t
						      ,index)
				       ,@(cddr item)))
	 ,@body))))
