(defpackage #:standard-devices
  (:use #:cl)
  (:nicknames #:std-devices)
  (:export
   #:make-device))

(in-package #:standard-devices)

(defgeneric make-device (frontend backend)
  (:documentation "Make standard devices."))

(defmethod make-device ((frontend zmq:dealer) (backend zmq:router))
  (%make-device frontend backend))

(defmethod make-device ((frontend zmq:sub) (backend zmq:pub))
  (%make-device frontend backend))

(defmethod make-device ((frontend zmq:pull) (backend zmq:push))
  (%make-device frontend backend))

(defun %make-device (frontend backend)
  (lambda ()
    (zmq:with-poll-list (polls (front frontend :pollin)
                               (back backend :pollin))
      (zmq:with-message (msg)
        (flet ((forward (source destination)
                 (zmq:recvmsg source msg)
                 (loop :while (zmq:rcvmore source)
                       :do
                          (zmq:sendmsg destination msg :send-more t)
                          (zmq:recvmsg source msg))
                 (zmq:sendmsg destination msg)))
          (loop
           (when (zmq:poll polls)
             (when (zmq:has-events-p front)
               (forward frontend backend))
             (when (zmq:has-events-p back)
               (forward backend frontend)))))))))