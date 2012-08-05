(defpackage #:performance-tests
  (:nicknames #:perf-tests)
  (:use #:common-lisp #:util)
  (:export
   #:inproc-lat
   #:inproc-thr))

(in-package #:performance-tests)

(declaim (optimize (speed 3)))

(defun make-lat-worker (ctx message-count)
  (declare (type fixnum  message-count))
  (lambda ()
    (zmq:with-socket (rep ctx :rep :connect "inproc://lat-test")
      (zmq:with-message (msg)
        (dotimes (i message-count)
          (zmq:sendmsg rep (zmq:recvmsg rep msg)))))))

(defun inproc-lat (message-size message-count)
  (declare (type fixnum message-size message-count))
  (zmq:with-context (ctx)
    (zmq:with-socket (req ctx :req
                          :bind "inproc://lat-test")
      (let ((worker (bt:make-thread (make-lat-worker ctx message-count)
                                    :name "worker")))
        (declare (ignore worker))
        (zmq:with-message (msg message-size)
          (print (/ (with-stopwatch
                      (dotimes (x message-count)                         
                        (zmq:sendmsg req msg)
                        (zmq:recvmsg req msg)
                        (unless (eql (zmq:size msg) message-size)
                          (error "Incorrect message size"))))               
                    (* message-count 2.0))))))))

(defun make-thr-worker (ctx message-count message-size)
  (declare (type fixnum message-count message-size))
  (lambda ()
    (zmq:with-socket (push ctx :push
                           :connect "inproc://thr-test")
      (zmq:with-message (msg message-size)
        (with-slots ((ptr little-zmq::msg-t))
            msg
          (dotimes (i message-count)      
            (zmq:sendmsg push msg)
            (%zmq::msg-init-size ptr message-size)))))))

(defun inproc-thr (message-size message-count)
  (declare (type fixnum message-count message-size))
  (zmq:with-context (ctx)
    (zmq:with-socket (pull ctx :pull
                           :bind "inproc://thr-test")
      (let ((worker (bt:make-thread
                     (make-thr-worker ctx message-count message-size)
                     :name "worker")))
        (declare (ignore worker))
        (zmq:with-message (msg)
          (zmq:recvmsg pull msg)
          (let* ((elapsed
                   (with-stopwatch
                     (loop :for x fixnum :from 1 :below message-count
                           :do
                           (zmq:recvmsg pull msg)
                           (unless (= (zmq:size msg) message-size)
                             (error "Incorrect message size")))))
                 (throughput (* (/ message-count elapsed) 1000000.0))
                 (megabits (/ (* throughput message-size 8) 1000000.0)))
            (values throughput megabits)))))))