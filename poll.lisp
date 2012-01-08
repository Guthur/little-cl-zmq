(in-package #:little-zmq)

(defclass poll-item ()
  ((pollitem-ptr
    :initarg :pollitem-ptr
    :reader pollitem-ptr)
   (poll-socket
    :initarg :poll-socket
    :reader poll-socket)
   (pollin
    :initarg :pollin
    :initform nil
    :reader pollin)
   (pollout
    :initarg :pollout
    :initform nil
    :reader pollout)
   (pollerr
    :initarg :pollerr
    :initform nil
    :reader pollerr)))

(defmethod initialize-instance :after ((poll-item poll-item) &key)
  (with-slots ((skt poll-socket)
	       (pollin pollin)
	       (pollout pollout)
	       (pollerr pollerr))
      poll-item
    (cffi:with-foreign-slots ((%zmq::socket %zmq::events)
			      (pollitem-ptr poll-item)
			      %zmq::pollitem-t)
      (setf %zmq::socket (slot-value skt '%zmq::ptr)
	    %zmq::events (+ (if pollin %zmq::+pollin+ 0)
		      (if pollout %zmq::+pollout+ 0)
		      (if pollerr %zmq::+pollerr+ 0))))))

(defun fire-events (poll-item)
  (declare (type poll-item poll-item))
  (with-slots ((socket poll-socket)
	       (pollitem-ptr pollitem-ptr)
	       (pollin pollin)
	       (pollout pollout)
	       (pollerr pollerr))
      poll-item
    (cffi:with-foreign-slots ((%zmq::revents) pollitem-ptr %zmq::pollitem-t)
      (when (and pollin
		 (not (zerop (boole boole-and %zmq::revents %zmq::+pollin+))))
	(funcall pollin socket %zmq::revents))
      (when (and pollout
		 (not (zerop (boole boole-and %zmq::revents %zmq::+pollout+))))
	(funcall pollout socket %zmq::revents))
      (when (and pollerr
		 (not (zerop (boole boole-and %zmq::revents %zmq::+pollerr+))))
	(funcall pollerr socket %zmq::revents)))))

(defun poll (poll-items num-items timeout eintr-retry)
  (if eintr-retry
      (with-zmq-eintr-retry
	(%zmq::poll poll-items num-items timeout))
      (%zmq::poll poll-items num-items timeout)))

(defun repoll ()
  (return-from repoll))

(defmacro with-polls ((poll-items
		       &key (timeout -1) (loop nil) (eintr-retry t))
		      &body body)
  (alexandria:with-gensyms (poll-item-list again)
    `(cffi:with-foreign-object (poll-foreign-array
				'%zmq::pollitem-t
				,(length poll-items))
       (let ((,poll-item-list
	       (list ,@(loop :for poll-item :in poll-items
			     :for item :from 0
			     :collect
			     `(make-instance 'poll-item
					     :poll-socket
					     ,(car poll-item)
					     :pollitem-ptr
					     (cffi:mem-aref poll-foreign-array
							    '%zmq::pollitem-t
							    ,item)
					     ,@(cdr poll-item))))))
	 (tagbody
	    ,again
	    (poll poll-foreign-array ,(length poll-items) ,timeout ,eintr-retry)
	    (block repoll
	      (loop :for item :in ,poll-item-list :do
		(fire-events item)))
	    ,@body
	    ,(when loop
	       `(go ,again)))))))