;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Package: CLIM-ENV; Base: 10; Lowercase: Yes -*-

;;; Copyright (c) 1994-2000, Scott McKay.
;;; Copyright (c) 2001-2003, Scott McKay and Howard Shrobe.
;;; All rights reserved.  No warranty is expressed or implied.
;;; See COPYRIGHT for full copyright and terms of use.

(in-package :clim-env)

;;; Random debugging and inspection commands

;; Provide integration with CLOS operations -- JCMa 12/14/2001.
(define-presentation-type class-specifier ()
  :inherit-from 'symbol)

;; Need a little more magic 
#|
(define-presentation-translator class-specifier-to-class-translator 
    (class-specifier class clos
     :gesture nil
     :menu nil
     :tester ((object) (find-class object nil)))
  (object presentation)
  (declare (ignore presentation))
  (find-class object t))
|#

(defun display-symbol-and-definitions (symbol symbol-types &key (stream *standard-output*))
  (let ((printed-symbol nil)
	(printed-delimiter nil))
    ;; We only want to print the symbol name if at least one of the
    ;; WHEN clauses below is true, and we only want to print the
    ;; post-symbol delimiter when we know that there is at least one
    ;; definition type following.
    (labels ((print-definition-type (symbol type-name)
	       (unless printed-symbol
		 ;; Binding *PACKAGE* to NIL forces the short name of the
		 ;; package to be printed
		 (let ((*package* #+Genera nil #-Genera (find-package :keyword)))
		   (fresh-line stream)
		   (write-string "  " stream)
		   (present symbol (cond ((fboundp symbol) 'function-spec)
					 ((boundp symbol) 'form)
					 ((find-class symbol nil) 'class-specifier)
					 (t 'expression))
			    :stream stream))
		 (setq printed-symbol t))
	       (when type-name
		 (with-text-face (stream :italic)
		   (cond (printed-delimiter
			  (write-string ", " stream))
			 (t (write-string " -- " stream)
			    (setq printed-delimiter t)))
		   (write-string type-name stream))))
	     (type-matches (type-name)
	       (or (member ':all symbol-types)
		   (member type-name symbol-types))))
      (declare (dynamic-extent #'print-definition-type #'type-matches))
      ;; The following WHEN clauses check for the various ways that the
      ;; symbol may be defined.
      (when (type-matches :unbound)
	;; No value or definition, but symbol does exist
	(print-definition-type symbol nil))
      (when (and (type-matches :function)
		 (fboundp symbol))
	(print-definition-type
	 symbol
	 (handler-case
	     (with-output-to-string (s)
	       (write-string "Function " s)
	       (print-lambda-list (function-arglist symbol) s :brief t))
	   (error () "Undecipherable function"))))
      (when (and (type-matches :variable)
		 (boundp symbol))
	(print-definition-type symbol "Bound"))
      (when (and (type-matches :class)
		 (not (null symbol))
		 (find-class symbol nil))
	(print-definition-type symbol "Class"))
      (when (and (type-matches :presentation-type)
		 (not (null symbol))
		 (find-presentation-type-class symbol nil))
	(print-definition-type symbol "Presentation Type"))
      (force-output stream))))

(define-command (com-find-symbols :name t :command-table inspection)
    ((strings '(sequence string) :prompt "substring(s)"
	      :documentation "Substrings of the symbol to find")
     &key
     (packages '(token-or-type (:all) (sequence package))
	       :default :all :prompt "packages to search"
	       :documentation "Packages in which to search")
     (conjunction '(member and or) :default 'and
		  :documentation "AND or OR of the strings")
     (imported-symbols 'boolean :default nil :mentioned-default t
		       :documentation "Search imported symbols")
     (used-by 'boolean :default nil :mentioned-default t
	      :documentation "Search packages used by these packages")
     (using 'boolean :default nil :mentioned-default t
	    :documentation "Search packages that use these packages")
     (types '(subset :variable :function :class :presentation-type :unbound :all)
	    :default '(:all) :prompt "symbol types"
	    :documentation "Kinds of symbols to search for")
     (external-symbols 'boolean :default t :mentioned-default t
		       :documentation "Don't show internal symbols of a package"))
  (with-frame-standard-output (stream)
    (when (null types) (setq types '(:all)))
    (with-text-face (stream :italic)
      (format stream "~&Searching ")
      (if (eql packages :all)
	(write-string "all packages" stream)
	(format-textual-list packages #'(lambda (p s)
					  (present p 'package :stream s))
			     :conjunction "and" :stream stream))
      (when (or using used-by)
	(cond ((and using used-by)
	       (write-string " and packages using and used by" stream))
	      (using
	       (write-string " and packages using" stream))
	      (used-by
	       (write-string " and packages used by" stream)))
	(if (or (eql packages :all)
		(and (listp packages) (> (length packages) 1)))
	  (write-string " them" stream)
	  (write-string " it" stream)))
      (format stream " for ~:[~A~;all~*~] symbols with names containing "
	(member :all types)
	(with-output-to-string (s)
	  (format-textual-list types #'(lambda (thing stream)
					 (format stream "~(~A~)" thing))
			       :conjunction "and" :stream s)))
      (format-textual-list strings #'prin1
			   :conjunction (if (eql conjunction 'and) "and" "or") :stream stream))
    (when (eql packages :all)
      (setq packages (list-all-packages)))
    (let ((this-package nil)
	  (package-name-printed nil))
      (labels ((find-symbols (symbol package)
		 (when (and (or imported-symbols
				(eql (symbol-package symbol) package))
			    (let ((symbol-name (symbol-name symbol)))
			      (if (eql conjunction 'and)
				(every #'(lambda (string)
					   (search string symbol-name :test #'char-equal))
				       strings)
				(some #'(lambda (string)
					  (search string symbol-name :test #'char-equal))
				      strings))))
		   (unless package-name-printed
		     (with-text-face (stream :italic)
		       (format stream "~&In package ")
		       (present this-package 'package :stream stream))
		     (setq package-name-printed t))
		   (display-symbol-and-definitions symbol types :stream stream)))
	       (search-package (package)
		 (setq package-name-printed nil
		       this-package package)
		 #+Genera
		 (zl:mapatoms #'(lambda (symbol) (find-symbols symbol package))
			      package
			      ;; Don't search inherited symbols if we are going to search
			      ;; the used-by packages later anyway
			      (and imported-symbols (not used-by)))
		 #-Genera
		 (if external-symbols
		     (do-external-symbols (symbol package)
		       (find-symbols symbol package))
		   (do-symbols (symbol package)
		     (find-symbols symbol package))))
	       (map-over-packages (function)
		 (loop for package in packages doing
		   (funcall function package)
		   (when using
		     (dolist (usee (package-used-by-list package))
		       (unless (eql usee package)
			 (funcall function usee))))
		   (when used-by 
		     (dolist (user (cons package (package-use-list package)))
		       (unless (eql user package)
			 (funcall function user)))))))
	(declare (dynamic-extent #'find-symbols #'search-package #'map-over-packages))
	(map-over-packages #'search-package)))
    (with-text-face (stream :italic)
      (format stream "~& ... Done."))))

(define-command (com-show-function-arglist :name t :command-table inspection)
    ((function 'function-spec))
  (with-frame-standard-output (stream)
    (multiple-value-bind (arglist found-p)
	(let ((function (and (fboundp function) (fdefinition function))))
	  (and function (function-arglist function)))
      (cond (found-p
	     (present function 'function-spec :stream stream)
	     (write-string ": " stream)
	     (print-lambda-list arglist stream))
	    (t (format stream "There is no function named ~A" function))))))

(defun function-arglist (function)
  (declare (values arglist found-p values))
  #+Genera (multiple-value-bind (arglist values)
	       (sys:arglist function)
	     (values arglist t values))
  #+Cloe-Runtime (sys::arglist function)
  #+allegro (values (excl:arglist function) t nil)
  #+MCL(multiple-value-bind (args)
	   (ccl:arglist function)
	 (values args (or (not (null args)) (fboundp function)) nil))
  #+Lucid (values (lucid-common-lisp:arglist function) t nil)
  #+Lispworks (let ((arglist (#+Lispworks3.2 lw:function-lambda-list 
                              #-LispWorks3.2 hcl:function-lambda-list 
			      function)))
		(if (eql arglist :none)
		  (values nil nil nil)
		  (values arglist t nil)))) 

(defparameter *default-bug-report-system*
   #+Genera "Genera"
   #+Lispworks "LispWorks"
   #+allegro "Allegro"
   #+MCL "MCL") 

(define-command (com-report-bug :command-table debugging :name t)
    ((system 'string
	     :prompt "about system"
	     :default (or #+Genera dbg:*default-bug-report-recipient-system*
			  *default-bug-report-system*)
	     :documentation "System for which to report a problem"))
  (mail-bug-report :process-name "Mail from Report Bug command"
		   :system system)) 

;;--- Save Compiler Warnings
;;--- Show Compiler Warnings 

#+Genera 
(defun set-stack-size (size stack-type)
  (case stack-type
    (:control
     (setq size (min (floor sys:%address-space-zone-size 32)
		     (max size (+ sys:control-stack-overflow-margin 1_10)))))
    (:bind
     (setq size (min (floor sys:%address-space-zone-size 32)
		     (max size 100))))
    (:data
     (setq size (min (floor sys:%address-space-zone-size 32)
		     size))))
  (dbg:com-set-stack-size stack-type size))

#+MCL
(defun set-stack-size (size #+Genera stack-type)
  (setf (ccl::stack-group-maximum-size ccl::*current-stack-group*) size))

#+(or Genera MCL)
(define-command (com-set-stack-size :command-table debugging :name t)
    ((size '((integer 0))
	   :provide-default nil :prompt "Size of new stack")
     #+Genera (stack-type '(member :control :bind :data) :prompt "Stack to grow"))
  (set-stack-size size #+Genera stack-type)) 

(define-command (com-show-compiled-code :command-table debugging :name t)
    ((function 'function-spec :gesture nil))
  (with-frame-standard-output (stream)
    (show-code-for-function function :headerp nil :show-source nil :stream stream)))

(define-command (com-show-source-code :command-table debugging :name t)
    ((function 'function-spec :gesture nil))
  (with-frame-standard-output (stream)
    (show-code-for-function function :headerp nil :show-source t :stream stream)))


;;; Breakpoint commands

;;--- Set Breakpoint (debugger will inherit these four commands)
;;--- Clear Breakpoint
;;--- Clear All Breakpoints
;;--- Show Breakpoints 

;;; Presentation-oriented commands

(define-command (com-describe-presentation :command-table presentations :name t)
    ((presentation 'presentation))
  (describe presentation))

;;--- What other presentation inspection and input context commands do we need?
(define-gesture-name :describe-presentation :pointer-button (:middle :super))

(define-presentation-to-command-translator describe-presentation
    (t com-describe-presentation presentations
     :documentation "Describe this presentation"
     :gesture :describe-presentation)
  (object presentation)
  (declare (ignore object))
  (list presentation))

(define-command (com-clear-output-history :command-table presentations :name t) ()
  (window-clear (frame-standard-output *application-frame*)))

(define-presentation-type buffer-name ()
  :history t
  :inherit-from t)

(define-presentation-method describe-presentation-type ((type buffer-name) stream plural-count)
  (default-describe-presentation-type "buffer" stream plural-count))

(define-presentation-method presentation-typep (object (type buffer-name))
  (stringp object))

;;; Interesting observation here:
;;; CLIM will not force in the default value when no input is provided
;;; unless the accept method signals some sort of parse error.
;;; (Note that string and char ptypes don't do that and so they behave oddly)
;;; If you accept a (string 5) and then hit enter, it will provide the default value
;;; (if provided) even if the default is a different size than 5.
;;; If you accept a (string *), then hitting enter doesn't force in the default.
;;;   That's a bad implementation I guess.
;;;
;;; Anyhow, I explicitly signal a parse error here if the token read is empty in order
;;; to get the normally expected behavior.

(define-presentation-method accept ((type buffer-name) stream (view textual-view) &key)
  (let ((token (read-token stream)))
    (if (= (length token) 0)
	(simple-parse-error "Read 0 length buffer name")
      (values token type))))

(define-presentation-type output-destination ()
    :history t
    :inherit-from t)

(defparameter *destination-types* '(:pathname :buffer))

(defparameter *destination-ptype-alist*
    '((:pathname pathname "pathname" "Enter a pathname")
      (:buffer buffer-name "buffer" "Enter an editor buffer name")))

(define-presentation-method clim:accept ((type output-destination) stream (view clim:textual-view) &key)
  (clim:with-delimiter-gestures (#\Space)
    (let (dtype place delimiter)
      (clim:with-accept-help
	  ((:subhelp #'(lambda (stream action string)
			 (declare (ignore action string))
			 (write-string "Enter the destination type." stream))))	
	(setq dtype (clim:accept `(clim:member ,@*destination-types*)
				  :stream stream :view view :prompt "type")))
      (destructuring-bind (dtype type prompt help) (assoc dtype *destination-ptype-alist*)
	(when (eql type nil)
	  (return-from clim:accept (list dtype nil)))
	;; Read the delimiter -- it should be a space, but if it is not,
	;; signal a parse-error.
	(setq delimiter (clim:stream-peek-char stream))
	(cond ((char-equal delimiter #\Space)
	       (stream-read-char stream)
	       (clim:with-accept-help
		   ((:subhelp #'(lambda (stream action string)
				  (declare (ignore action string))
				  (write-string help stream))))
		 (setq place (accept type :stream stream :view view :prompt prompt))))
	      (t (simple-parse-error "Invalid delimiter: ~S" delimiter)))
	(list dtype place)))))

(define-presentation-method clim:present (object (type output-destination) stream (view clim:textual-view) &key)
  ;; Just print the two parts of the object separated by a space.
  (destructuring-bind (dtype place) object
    (if place
	(format stream "~:(~A~) ~A" dtype place)
      (format stream "~:(~A~)" dtype))))

;; Only lists whose two elements are right
(define-presentation-method clim:presentation-typep (object (type output-destination))
  (and (listp object)
       (= (length object) 2)
       (not (null (assoc (first object) *destination-ptype-alist*)))))

(define-command (com-copy-output-history :command-table presentations :name t)
    ((output-destination 'output-destination
			 :history 'output-destination
			 :provide-default t
			 :default-type 'output-destination))
  (destructuring-bind (type value) output-destination
    (case type
      (:buffer
       (copy-history-to-editor-buffer *standard-output* (string value)))
      (:pathname
       (with-open-file (stream value :direction :output)
	 (copy-textual-output-history *standard-output* stream))))))

#+allegro
(lep:define-reply copy-output-history-session (lep::compute-reply-session)
  (source-stream buffer-name)
  (lep::with-output-to-temp-buffer (stream buffer-name)
    (clim-environment::copy-textual-output-history source-stream stream))
  (values)
  )

#+allegro
(defmethod lep:session-options-function-and-arguments-for-editor
    ((session copy-output-history-session) &key fspec)
  (declare (ignore fspec))
  (list nil 'ignore ))

#+allegro
(defun copy-history-to-editor-buffer (source-stream buffer-name &rest options)
  "Copy the window to an editor buffer"
  (apply #'lep::make-session
	 nil
	 'copy-output-history-session
	 :source-stream source-stream
	 :buffer-name buffer-name
	 :lisp-initiated-p t
	 options))


;;; Portable process extensions

#+MCL
(ccl:require "New-Scheduler" #p"ccl:library;new-scheduler")

#+allegro
(eval-when (:compile-toplevel :load-toplevel :execute)
  (setf (excl:package-definition-lock (find-package :clim-sys)) nil))

(defun clim-sys::process-run-reasons (process)
  #+Genera (si:process-run-reasons process)
  #+MCL (ccl:process-run-reasons process)
  #+allegro (mp::process-run-reasons process))

(defun clim-sys::process-arrest-reasons (process)
  #+Genera (si:process-arrest-reasons process)
  #+MCL (ccl:process-arrest-reasons process)
  #+allegro (mp::process-arrest-reasons process))

(defun clim-sys::process-enable-arrest-reason (process &optional (reason :user))
  #+Genera (si:process-enable-arrest-reason process reason)
  #+MCL (ccl:process-enable-arrest-reason process reason)
  #+allegro (mp:process-add-arrest-reason process reason))

(defun clim-sys::process-disable-arrest-reason (process &optional (reason :user))
  #+Genera (si:process-disable-arrest-reason process reason)
  #+MCL (ccl:process-disable-arrest-reason process reason)
  #+allegro (mp:process-revoke-arrest-reason process reason))

(defun clim-sys::process-priority (process)
  "Returns an integer denoting priority of PROCESS."
  #+Genera (process:process-process-priority process)
  #+MCL (ccl:process-priority process)
  #+Lispworks 0
  #+allegro (mp::process-priority process))

(defun clim-sys::process-cpu-time (process)
  "Returns the number of seconds PROCESS has consumed."
  #+Genera (process:process-cpu-time process)
  #+MCL (floor (ccl::process-total-run-time process) 60)
  #+Lispworks 0
  #+allegro (round (mp::process-cpu-msec-used process) 1000))

(defun clim-sys::process-idle-time (process)
  "Returns the number of seconds PROCESS has been idle."
  #+(or Lispworks allegro)
  (declare (ignore process))
  #+Genera (process:process-idle-time process)
  #+MCL (if (eq process ccl::*current-process*)
          0.0
          (/ (ccl::%tick-difference
              (ccl::get-tick-count)
              (ccl::process-last-run-time process))
             60.0))
  #+Lispworks 0
  #+allegro 0)

(defun clim-sys::process-percent-utilization (process)
  "Returns a float indicating the percentage of the Lisp that PROCESS consumes."
  #+ (or Lispworks allegro) 
  (declare (ignore process))
  #+Genera(process::percent-utilization process)
  #+MCL (ccl::process-utilization process)
  #+Lispworks 0
  #+allegro 0) 

(defun clim-sys::debug-process (process)
  #+Genera (dbg:dbg process)
  #+MCL (ccl:process-interrupt (ccl::require-type process 'ccl::process) 
			       #'(lambda ()
				   (let ((ccl::*interrupt-level* 0))
				     (break))))
  #+Allegro (mp:process-interrupt process #'(lambda () (break "Process interrupted!"))))

#+allegro
(eval-when (:compile-toplevel :load-toplevel :execute)
  (setf (excl:package-definition-lock (find-package :clim-sys)) t))


;;; Commands for processes

(defun confirm-destructive-process-command (process type string)
  (case type
    ((t) (yes-or-no-p "~A process ~A" string process))
    ((:mouse :pointer) (pointer-yes-or-no-p
                         (format nil "~A process ~A" string process)
			 :foreground +black+
                         :background (find-named-color
                                       "orange-red" (frame-palette *application-frame*))))
    (otherwise t)))

(define-command (com-interrupt-process :command-table processes :name t ) 
  ((process 'process :provide-default nil))
  (mp:process-interrupt process 'break)
	     )


(define-command (com-kill-process :command-table processes :name t)
    ((process 'process
	      :provide-default nil)
     &key
     (confirm '(token-or-type (:mouse) boolean)
	      :default nil :mentioned-default t
	      :documentation "Request confirmation before killing the process"))
  (when (confirm-destructive-process-command process confirm "Kill")
    (clim-sys:destroy-process process)))

(define-presentation-to-command-translator kill-process
   (process com-kill-process processes
    :gesture nil)
   (object)
  (list object :confirm :mouse)) 

(define-command (com-stop-process :command-table processes :name t)
    ((process 'process :provide-default nil :gesture nil))
  (clim-sys::process-enable-arrest-reason process)) 

(define-command (com-start-process :command-table processes :name t)
    ((process 'process :provide-default nil :gesture nil))
  (dolist (reason (clim-sys::process-arrest-reasons process))
    (clim-sys::process-disable-arrest-reason process reason))) 

(define-command (com-restart-process :command-table processes :name t)
    ((process 'process :provide-default nil)
     &key
     (confirm '(token-or-type (:mouse) boolean)
	      :default nil :mentioned-default t
	      :documentation "Request confirmation before restarting the process"))
  (when (confirm-destructive-process-command process confirm "Reset")
    (clim-sys:restart-process process)))

(define-presentation-to-command-translator restart-process
   (process com-restart-process processes
    :gesture nil)
   (object)
  (list object :confirm :mouse))

(define-command (com-debug-process :command-table processes :name t)
    ((process 'process :provide-default nil :gesture nil))
  (clim-sys::debug-process process)) 

(defun filter-processes (processes &key name state priority-above priority-below unarrested
					#+Genera system)
  (flet ((name-p (p)
	   (loop with process-name = (clim-sys:process-name p)
	         for n in name
	         always (search n process-name :test #'char-equal)))
	 (state-p (p)
	   (search state (clim-sys:process-state p) :test #'char-equal))
	 (priority-above-p (p)
	   (> (clim-sys::process-priority p) priority-above))
	 (priority-below-p (p)
	   (> priority-below (clim-sys::process-priority p)))
	 (unarrested-p (p)
	   (and (clim-sys::process-run-reasons p)
		(null (clim-sys::process-arrest-reasons p))))
	 #+Genera
	 (system-p (p)
	   (not (ldb-test process::process-debug-system-process
			  (process::process-debug-flag process)))))
    (declare (dynamic-extent #'name-p #'state-p #'priority-above-p #'priority-below-p))
    (let (filters)
      (macrolet ((collect-filters (&rest clauses)
		   `(progn 
		      ,.(loop for (var pred) in clauses
			      collect `(when ,var (push ,pred filters))))))
	(collect-filters
	 (name #'name-p)
	 (state #'state-p)
	 (priority-above #'priority-above-p)
	 (priority-below #'priority-below-p)
	 (unarrested #'unarrested-p)
	 #+Genera (system #'system-p)))
      (if filters
	(loop for process in processes
	      when (loop for filter in filters
		         always (funcall filter process))
	        collect process)
	processes)))) 

(define-presentation-type process-idle-time () 
  :inherit-from `((integer)))

(define-presentation-method present
    (idle-time (type process-idle-time) stream (view textual-view) &key)
  (cond ((null idle-time) (write-string "forever" stream))
        ;; ((zerop idle-time))
        ((< idle-time 60) (format stream "~4,2f sec" idle-time))
        ((< idle-time 3600) (format stream "~D min" (floor idle-time 60)))
        (t (format stream "~D hr" (floor idle-time 3600))))) 

#|| ;; remaining Lispm Args for show process command
(recent 'time:time-interval :default nil :prompt "within last"
	:mentioned-default #.(accept-from-string 'time:time-interval "1 minute")
	:documentation "Show only processes that have run this recently.")
(idle 'time:time-interval :default nil :prompt "for at least"
      :mentioned-default #.(accept-from-string 'time:time-interval "1 minute")
      :documentation "Show only processes that have not run for this amount of time.")
||# 

(define-command (com-show-processes :command-table processes :name t)
    (&key
     (name '(sequence (string))
	   :prompt "process names or substrings"
	   :default nil
	   :documentation "Shows only the named processes or, for any name which is a string, 
shows all processes which have a name containing that string.")
     (state '(or string null) :default nil :prompt "matching substring"
	    :documentation "Show only processes whose states contain this substring.")
     (order '((member :none :percent :name :idle :cpu))
	    :default :none
	    :documentation "Sorting method for processes list.")
     (priority-above '(or integer null) :default nil
		     :documentation "Show only processes of higher priority than this.")
     (priority-below '(or integer null) :default nil
		     :documentation "Show only processes of lower priority than this.")
     (unarrested 'boolean :default nil :prompt "unarrested processes only"
		 :mentioned-default 'T
		 :documentation "Show only processes are not arrested.")
     #+Genera (system 'boolean :default t :prompt "system processes"
		      :documentation "Show system processes too.")
     #+Genera (detailed 'boolean :default process::*show-detailed-process-utilization*
			:mentioned-default 't
			:documentation "Show more detailed internal breakdown of process utilization."))
  (let* ((processes (clim-sys:all-processes))
	 (filtered-processes (filter-processes processes
					       :name name :state state
					       :priority-above priority-above
					       :priority-below priority-below 
					       :unarrested unarrested
					       #+Genera :system #+Genera system)))
    (with-frame-standard-output (stream)
      (cond (filtered-processes
	     (ecase order		;provide resortable output for slickness
	       (:none nil)
	       (:name 
		(setq filtered-processes
		      (stable-sort (if (eq processes filtered-processes)
				     (copy-list processes)
				     filtered-processes) 
				   #'string< :key #'clim-sys::process-name)))
	       (:percent 
		(setq filtered-processes
		      (stable-sort (if (eq processes filtered-processes)
				     (copy-list processes)
				     filtered-processes) 
				   #'> :key #'clim-sys::process-percent-utilization)))
	       (:idle 
		(setq filtered-processes
		      (stable-sort (if (eq processes filtered-processes)
				     (copy-list processes)
				     filtered-processes) 
				   #'> :key #'clim-sys::process-idle-time)))
	       (:cpu 
		(setq filtered-processes
		      (stable-sort (if (eq processes filtered-processes)
				     (copy-list processes)
				     filtered-processes) 
				   #'> :key #'clim-sys::process-cpu-time))))
	     (formatting-table (stream :x-spacing "   ")
	       (formatting-row (stream)
		 (with-text-face (stream :italic)
		   (formatting-cell (stream)
		     (write-string "Process Name" stream))
		   (formatting-cell (stream)
		     (write-string "State" stream))
		   (formatting-cell (stream)
		     (write-string "Priority" stream))
		   (formatting-cell (stream)
		     (write-string "CPU" stream))
		   (formatting-cell (stream)
		     (write-string "Idle" stream))
		   #-Genera (formatting-cell (stream)
			      (write-string " % Utilization" stream))
		   #+Genera (cond (detailed
				   (formatting-cell (stream)
				     (write-string " Real %" stream))
				   (formatting-cell (stream)
				     (write-string " % CPU" stream))
				   (formatting-cell (stream) 
				     (write-string " % Page" stream)))
				  (t (formatting-cell (stream)
				       (write-string " % Utilization" stream))))))
	       (dolist (process filtered-processes)
		 (formatting-row (stream)
		   (formatting-cell (stream)
		     (present process 'process :stream stream))
		   (formatting-cell (stream) 
		     (write-string (clim-sys:process-state process) stream))
		   (formatting-cell (stream) 
		     (write (clim-sys::process-priority process) :base 10. :stream stream))
		   (formatting-cell (stream) 
		     (present (clim-sys::process-cpu-time process) 'number :stream stream))
		   (formatting-cell (stream) 
		     (present (clim-sys::process-idle-time process) 'process-idle-time :stream stream))
		   #-Genera (formatting-cell (stream)
			      (format stream "~1,1,4$%" (clim-sys::process-percent-utilization process)))
		   #+Genera (cond (detailed
				   (formatting-cell (stream)
				     (format stream "~1,1,4$%"
				       (clim-sys::process-percent-utilization process)))
				   (formatting-cell (stream)
				     (format stream "~1,1,4$%"
				       (process::percent-cpu process)))
				   (formatting-cell (stream)
				     (format stream "~1,1,4$%"
				       (process::percent-paging process))))
				  (t (formatting-cell (stream)
				       (format stream "~1,1,4$%"
					 (clim-sys::process-percent-utilization process)))))))))
	    (t (macrolet ((make-failure-report (&body specs)
			    `(nconc ,.(loop for (test format-string . args) in specs
					    collect `(when ,test
						       (list (list ,format-string ,@args)))))))
		 (format stream "~&No process exists ")
		 (format-textual-list
		   (make-failure-report 
		     (name "with ~{~#[nothing~;~S~;~S or ~:;~S, ~]~:} as a substring of its name" name)
		     (state "with ~S as a substring of its state" state)
		     (priority-above "with priority > ~D" priority-above)
		     (priority-below "with priority < ~D" priority-below)
		     #+Genera (system "that wasn't a system process")
		     (unarrested "that wasn't arrested"))
		   #'(lambda (item stream) (apply #'format stream item))
		   :stream stream :conjunction "and")
		 (format stream ".~%")))))))




;;; Tracing commands

#+MCL
(defun ccl::trace-function (function-spec &key (before :print) (after :print) step)
  (etypecase function-spec
    (symbol (ccl::%trace function-spec :before before :after after :step step))
    (cons 
     (cond ((null (cdr function-spec))
            (ccl::%trace (car function-spec)  :before before :after after :step step))
           ((member (car function-spec) '(:method ccl::setf))
            (ccl::%trace function-spec  :before before :after after :step step))
           (t (dolist (item function-spec)
                (ccl::%trace item  :before before :after after :step step)))))))

;;--- This should take a bunch of tracing options
;;--- There should be a dialog interface to these options, too
(define-command (com-trace-function :command-table tracing :name t)
    ((functions '(sequence function-spec) :provide-default nil :prompt "function(s)"
		:documentation "Functions to trace.")
     &key
     #+(or Genera Lispworks)
     (break 'boolean :default nil :mentioned-default t
	    :documentation "Break on function entry")
     #+allegro
     (before 'boolean :default nil :mentioned-default t
	     :documentation "Break on function entry")
     #+allegro
     (after 'boolean :default nil :mentioned-default t
	    :documentation "Break on function exit")
     #+MCL
     (before '(member-alist (("Break" . :break) ("Print" . :print) ("No Action" . nil)) :test equalp) :default :print :mentioned-default :break
	     :documentation "Action before function call.")
     #+MCL
     (after '(member-alist (("Break" . :break) ("Print" . :print) ("No Action" . nil)) :test equalp) :default :print :mentioned-default :break
	    :documentation "Action after function call.")
     #+MCL 
     (step 'boolean :default nil :mentioned-default t
	   :documentation "Single step function."))
  (dolist (function functions)
    #+(or Genera Lispworks) (eval `(trace (,function :break ,break)))
    #+allegro (eval `(trace ,function ,@(and before (list :break-before 'true))
			              ,@(and after (list :break-after 'true))))
    #+MCL (ccl::trace-function function :before before :after after :step step)
    ;; Thank you, dpANS, for this little gift
))

(define-command (com-untrace-function :command-table tracing :name t)
    ((functions '(token-or-type (:all) (sequence function-spec))
		:default :all
		:prompt "function(s)"))
  (if (eql functions :all)
    (untrace)
    ;; Thank you, dpANS, for this little gift
    (eval `(untrace ,@functions)))) 

(define-command (com-enable-condition-tracing :command-table tracing :name t)
    ((conditions '(sequence class)
		 :default '(error)
		 :prompt "classes"
		 :gesture nil))
  (with-frame-standard-output (stream)
    (let ((class-names (mapcar #'class-name conditions)))
      ;; Do a TYPEP check to verify that CONDITIONS is a valid type spec.
      ;; Better this than breaking SIGNAL and ERROR.
      (if (every #'(lambda (c) (subtypep c 'condition)) conditions)
	(setq *break-on-signals* class-names)
	(format stream "~&Some of the classes in ~S are not conditions" class-names)))))

(define-command (com-disable-condition-tracing :command-table tracing :name t) ()
   (setq *break-on-signals* nil))


;;--- Monitor Variable
;;--- Show Monitored Locations
;;--- Unmonitor Variable

