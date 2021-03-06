;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Package: CLIM-ENV; Base: 10; Lowercase: Yes -*-

;;; Copyright (c) 1994-2000, Scott McKay.
;;; Copyright (c) 2001-2003, Scott McKay and Howard Shrobe.
;;; All rights reserved.  No warranty is expressed or implied.
;;; See COPYRIGHT for full copyright and terms of use.

(in-package :clim-env)

;;; General utility commands

;;--- Show Hosts
;;--- Show Users (aka, "finger")

(define-command (com-show-time :command-table utilities :name t) ()
  (with-frame-standard-output (stream)
    (fresh-line stream)
    (write-string "The current time is " stream)
    (present (get-universal-time) 'universal-time :stream stream)))

#-MCL
(define-command (com-set-time :command-table utilities :name t)
    ((time 'universal-time
	   :default (get-universal-time)))
  #-genera (declare (ignore time))
  (with-frame-standard-output (stream)
    #+Genera (progn
	       (time:initialize-timebase time nil)
	       (time:set-calendar-clock time))
    (fresh-line stream)
    (write-string "The time is now " stream) 
    (present (get-universal-time) 'universal-time :stream stream)))

