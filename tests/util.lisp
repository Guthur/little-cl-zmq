(defpackage #:util
  (:use #:common-lisp)
  (:export #:with-stopwatch))

(in-package #:util)

(defparameter +clock-realtime+ 0)
(defparameter +clock-monotonic+ 1)
(defparameter +clock-process-cputime-id+ 2)
(defparameter +clock-thread-cputime-id+ 3)
(defparameter +clock-monotonic-raw+ 4)
(defparameter +clock-realtime-coarse+ 5)
(defparameter +clock-monotonic-coarse+ 6)
(defparameter +clock-boottime+ 7)
(defparameter +clock-realtime-alarm+ 8)

(cffi:defcstruct time-spec
  "Time Spec"
  (seconds :int)
  (nano :long))

(cffi:defcfun "clock_getres" :int
  "Get clock precision"
  (clock-id :int)
  (timespec :pointer))

(cffi:defcfun "clock_gettime" :int
  "Get clock time"
  (clock-id :int)
  (timespec :pointer))

(cffi:defcfun "clock_settime" :int
  "Set clock time"
  (clock-id :int)
  (timespec :pointer))

(defun get-clock-time (clock-id)
  (cffi:with-foreign-object (tspec 'time-spec)
    (let ((ret (clock-gettime clock-id tspec)))
      (if (zerop ret)
          (values (cffi:foreign-slot-value tspec 'time-spec 'seconds)
                  (cffi:foreign-slot-value tspec 'time-spec 'nano))
          (error "Error raised in C call")))))

(defun set-clock-time (clock-id seconds nano-seconds)
  (cffi:with-foreign-object (tspec 'time-spec)
    (setf (cffi:foreign-slot-value tspec 'time-spec 'seconds) seconds
          (cffi:foreign-slot-value tspec 'time-spec 'nano) nano-seconds)
    (unless (zerop (clock-settime clock-id tspec))
      (error "Error raised in C call"))))

(defun get-clock-res (clock-id)
  (cffi:with-foreign-object (tspec 'time-spec)
    (let ((ret (clock-getres clock-id tspec)))
      (if (zerop ret)
          (values (cffi:foreign-slot-value tspec 'time-spec 'seconds)
                  (cffi:foreign-slot-value tspec 'time-spec 'nano))
          (error "Error raised in C call")))))


(defmacro with-stopwatch (&body body)
  (alexandria:with-gensyms (ips)
    `(let* ((,ips (expt 10 9)))
       (multiple-value-bind (sec nano)
           (get-clock-time +clock-realtime+)
         (declare (type fixnum sec nano))
         ,@body
         (multiple-value-bind (esec enano)
             (get-clock-time +clock-realtime+)
           (declare (type fixnum esec enano))
           (/ (+ (* ,ips (- esec sec))
                 (- enano nano))
              1000))))))
