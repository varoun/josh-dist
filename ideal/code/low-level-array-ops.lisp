;;; -*- Mode: LISP; Syntax: Common-Lisp; Package: Ideal;  Base: 10 -*-

(in-package :ideal)



;;;;********************************************************
;;;;  Copyright (c) 1989, 1992 Rockwell International -- All rights reserved.
;;;;  Rockwell International Science Center Palo Alto Lab
;;;;********************************************************


;;;;;;;;;;;;;;;;;;;;;;;; Sampath ;;;;;;;;;;;;;;;;;;;;


(export '(CONDITIONING-CASE-P COMBINE-COND-CASES
			      FOR-ALL-COND-CASES
			      COPY-CONDITIONING-CASE
			      NODE-IN STATE-IN
			      MAKE-COND-CASE
			      MAKE-CONDITIONING-CASE))


;----------------------- LOWEST LEVEL ARRAY ACCESS AND CREATION ------------------------

; The node-list argument can be a lone node or a list of nodes.

(defun make-probability-array (node-or-node-list &key (initial-element 0)
			       (element-type 'NUMBER))
  (make-array (dimensions-of node-or-node-list)
	      :element-type element-type
	      :initial-element initial-element))

(defun dimensions-of (node-or-node-list)
  (cond
    ((node-p node-or-node-list)
     (+ *lowest-label-id-number* (number-of-states node-or-node-list)))
    ((listp node-or-node-list)
     (product-over (n node-or-node-list)(+ *lowest-label-id-number* (number-of-states n))))
    (t (error "Input ~A is neither a node nor a list of nodes." node-or-node-list))))

(defun read-probability-array (array cond-case reqd-nodes &key (main-node-case nil))
  (aref array (get-key-for-conditioning-case
		cond-case reqd-nodes :main-node-case main-node-case)))

(defun write-probability-array (array cond-case reqd-nodes value &key (main-node-case nil))
  (setf (aref array
	      (get-key-for-conditioning-case
		cond-case reqd-nodes :main-node-case main-node-case)) value))

;----- Getting a key into a probability array from a conditioning case

; This is used by the following fn. Is put ahead of it as it is needed in-line there.

(defun get-initial-prev-label-id-number (main-node-case)
  (cond
    ((null (node-in main-node-case)) 0)
    ((deterministic-node-p (node-in main-node-case)) 0)
    (t (label-id-number (state-in main-node-case)))))


; This function returns a unique key into a linear array for each
; main-node-case conditioning-node-case pair. The key is in the range: 0
; to (- (dimensions-of (cons main-node conditioning-nodes) 1). If
; *lowest-label-id-number* is 0 the key is in the range 0 to [ number of
; state combinations of main-node and conditioning nodes together] -
; 1. If main-node-case is not specified it is ignored and a key
; corresponding to conditioning case is returned.

; The conditioning-case has to be such that the node-id-nunbers of the
; nodes in the node-state-pairs are ascending from left to right. There
; cannot be two node-state pairs that have the same node. All the nodes
; in reqd-nodes have to be unique. It is an error if any of these
; conditions are not true in the inputs.

; The function will also break if a value node is a part of a
; conditioning case. The error is not explicit (not worth checking for)
; and will be seen as a call to (label-id-number nil).

; It is assumed that the state in each node-state pair in the
; conditioning case and main-node-case actually is a state of the node
; in the pair. No check is made for this (not worth  checking for). If
; such is not the case the function returns trash.


(defun get-key-for-conditioning-case (conditioning-case reqd-nodes &key main-node-case)
	; Setup variables
  (let* ((prev-label-id-number (get-initial-prev-label-id-number main-node-case))
	 (cond-case conditioning-case)(node-id-number *node-lowest-index*)
	 (key 0)(count-of-reqd-nodes 0)(node nil)(state nil))
    (declare (inline get-initial-prev-label-id-number))
	; Generate the key
    (loop
      (when (null cond-case)
	(setq key (+ key prev-label-id-number))(return))
      (setq node (caar cond-case) state (cdar cond-case) cond-case (cdr cond-case))
      (when (member node reqd-nodes)
	(cond	; Can also put in checks to make sure that states in node.state belongs
	; to node and that node is not value-node-p over here if necessary.
	  ((not (< node-id-number (node-id-number node)))	;** Look at comment at %%.
	   (error "The required nodes in cond-case ~A, are not in increasing order
                       of node id number (starting at node ~A)" conditioning-case node))
	  (t (incf count-of-reqd-nodes)
	     (setq key (* (+ key prev-label-id-number)
	; The following line should be a call to dimension-of,
	; but for speed it is coded this way.
			  (+ *lowest-label-id-number* (number-of-states node)))
		   prev-label-id-number (label-id-number state)))))
	;%% The following line used to be integrated into the line at ** but
	;Lucid complained and  so it is here.(Bug report from Bruce; 10 May)
      (setq node-id-number (node-id-number node)))
	; Return the key after an error check.
    (cond
      ((< count-of-reqd-nodes (length reqd-nodes))(show-error reqd-nodes conditioning-case))
      (t key))))

(defun show-error (reqd-nodes conditioning-case)
  (cond
    ((not (all-unique-p reqd-nodes))
     (error "The list of required nodes ~A has nodes that repeat" reqd-nodes))
    (t (error "All required nodes ~A are not part of cond-case ~A"
	      reqd-nodes conditioning-case))))

; True if no two elements of the list are the same

(defun all-unique-p (list &key (key  #'identity) (test #'eql))
  (loop
    (cond
      ((null (rest list)) (return t))
      ((member (funcall key (pop list)) list :key key :test test) (return nil)))))


; Access of the node and the state in an input of form ((node . state)).
; See prob-of.

(defun node-in (node-case)(caar node-case))

(defun state-in (node-case)(cdar node-case))

; For Mark 

(defsetf state-in (node-case)(value)
  `(setf (cdar ,node-case) ,value))


(proclaim '(inline node-in state-in))

;----------------------------------CONDITIONING CASE OPERATIONS -----------------------


; A conditioning case is represented as a list of dot pairs.  Each dot
; pair is of type node-structure . label-structure. The dot pair
; represents the state that the node is in. The nodes in the dot pairs
; are in increasing order of node-id-number when cdring down the
; conditioning-case.

; This function makes a properly ordered cond case by destructively
; changing the raw (unordered) cond case input to it.


(defun make-conditioning-case (raw-cond-case)
  (setq raw-cond-case (sort raw-cond-case #'< :key #'node-id-number-in-node-state-pair))
  (if (conditioning-case-p raw-cond-case) raw-cond-case))

(defun make-dummy-node-case (node)
  (cond
    ((node-p node)(list (list node)))
    (t (error "~A is not a node" node))))

(defun node-id-number-in-node-state-pair (n.s)
  (node-id-number (car n.s)))
(defun conditioning-case-p (cond-case)
  (dolist (node.state cond-case)
    (cond
      ((not (node-p (car node.state)))
       (error "The car of the pair ~A in raw cond case ~A is not a node."
	      (car node.state) cond-case))
      ((not (label-p (cdr node.state)))
       (error "The cdr of the pair ~A in raw cond case ~A is not a state label"
	      (cdr node.state) cond-case))
      ((not (eq (label-node (cdr node.state))(car node.state)))
       (error "The label ~A in the pair ~A in the cond-case ~A is not a
                 state-label of node ~A" (cdr node.state)
	      node.state cond-case (car node.state)))))
  (values t))

(defun make-cond-case (node-names state-names &optional (diagram *diagram*))
  (when (not (= (length node-names)(length state-names)))
    (error "The number of labels you have specified is not the same~
              as the number of nodes"))
  (let ((raw-cond-case nil)(n-names node-names)
	(s-names state-names) node-name node label)
    (loop
      (if (null n-names)(return))
      (setq node-name (pop n-names)
	    node (find-node node-name diagram)
	    label (find-label (pop s-names) node-name diagram))
      (push (cons node label) raw-cond-case))
    (make-conditioning-case raw-cond-case)))

(defun combine-cond-cases (&rest cond-cases)
  (reduce #'merge-cases cond-cases :initial-value nil))

; This fn is used in-line by the following fn.
(defun first-node-id-number (case)
  (node-id-number (car (first case))))

; This function is hacked to destructively splice in elements of case-2
; into case-1.  The case-1 argument is the final merged list that is
; returned. The result shares no structure with case-2. The hacking is
; to keep the number of conses small (= the length of case-2) and for
; speed. Did not use the CLISP fn merge coz there is no guarantee that
; it is efficient, i.e that it resuses the conses in case-1 and/or
; case-2.  Though CLtL says it does it doesn't in Genera (for example).

(defun merge-cases (case-1 case-2)
  (let ((end-pointer case-1))
    (declare (inline first-node-id-number))
    (loop (cond
	    ((null case-2) (return))
	    ((null case-1)(setq case-1 (copy-list case-2))(return))
	    ((< (first-node-id-number end-pointer) (first-node-id-number case-2))
	     (cond
	       ((null (cdr end-pointer)) (rplacd end-pointer (copy-list case-2))(return))
	       (t (setq end-pointer (cdr end-pointer)))))
	    (t (rplacd end-pointer (cons (car end-pointer) (cdr end-pointer)))
	       (rplaca end-pointer (car case-2))
	       (setq case-2 (cdr case-2) end-pointer (cdr end-pointer))))))
  (values case-1))

(defun copy-conditioning-case (case)
  (mapcar #'(lambda (n.s)(cons (car n.s)(cdr n.s))) case))

(defun equal-conditioning-cases (case1 case2)
  (every #'(lambda (n.s1 n.s2)
	     (and (eq (car n.s1)(car n.s2))
		  (eq (cdr n.s1)(cdr n.s2)))) case1 case2))

(defun cond-cases-match-on (node-list c-case-1 c-case-2)
  (let (n.s-1 n.s-2)
    (labels ((match-on-node (node)
	       (setq n.s-1 (find node c-case-1 :key #'car)
		     n.s-2 (find node c-case-2 :key #'car))
	       (if (null n.s-1)(error "Node ~A not found in cond-case ~A" node c-case-1))
	       (if (null n.s-2)(error "Node ~A not found in cond-case ~A" node c-case-2))
	       (eq (cdr n.s-1)(cdr n.s-2))))
      (every #'match-on-node node-list))))

(defun sort-by-id-number (node-list)
  (sort (copy-list node-list) #'< :key #'node-id-number))


;----  This stuff is used for checking the run time estimator fns results ----
; This stuff should be removed once the estimators have stabilized.

(defvar *operation-count* 0 "Count of number of combinatoric operations")

(defun reset-operation-count ()(setq *operation-count* 0))

; This macro basically is a no-op when being used outside Rockwell Palo Alto

(defmacro increment-operation-count-if-unchanged (form)
  (cond
    ((string= (long-site-name) "Rockwell Palo Alto Laboratory")
     (let ((old-count (gentemp "old-count")))
       `(let ((,old-count *operation-count*))
	  (prog1 ,form
		 (if (= *operation-count* ,old-count)(incf *operation-count*))))))
    (t form)))

;---- Generating conditioning cases to map over distributions -----

; The following four fns are used in-line by the macro that follows.

; Due to the change in syntax in for-all-cond-cases this fn has been
; changed to handle both a node-list or a single node as input.

(defun prepare-nodes-and-make-template (node-list)
  (let* ((template (cond
		     ((node-p node-list) (list (list node-list)))
		     (t (sort (mapcar #'list node-list) #'<
			      :key #'node-id-number-in-node-state-pair))))
	 (pointer-list (mapcar #'copy-list template))
	 (node nil))
    (map nil #'(lambda (node.state node.pointer)
		 (setf node (car node.state)
		       (cdr node.state)(first (state-labels node))
		       (cdr node.pointer) (rest (state-labels node))))
	 template pointer-list)
    (values template pointer-list)))

(defun rotate-pointer-list (pointer-list template)
  (block START
    (let (node)
      (map nil #'(lambda (node.pointer node.state)
		   (setq node (car node.state))
		   (cond
		     ((null (cdr node.pointer))
		      (setf (cdr node.state) (first (state-labels node))
			    (cdr node.pointer)(rest (state-labels node))))
		     (t (setf (cdr node.state)(pop (cdr node.pointer)))
			(return-from START t))))
	   pointer-list template))))

;This is so of the input node list is nil

(defun special-case-1-p (node-list)(null node-list))

; This is so if the input node list consists of a sole value or deterministic chance
; node which is the main-node.

(defun special-case-2-new-syntax-p (node-or-node-list)
  (and (node-p node-or-node-list)
       (deterministic-node-p node-or-node-list)
       (or (value-node-p node-or-node-list)(chance-node-p node-or-node-list))))

(defun special-case-2-old-syntax-p (node-or-node-list main-node)	
  (and (listp node-or-node-list)
	; Meaning Length =1 (special-case-1 eliminates nil)
       (null (rest node-or-node-list))
       (deterministic-node-p (first node-or-node-list))
       (or (value-node-p (first node-or-node-list))
	   (and main-node (chance-node-p (first node-or-node-list))))))

; The macro for-all-cond-cases is probably the most crucial bit of code
; in this system.  input-node-list is a list of nodes. The case-variable
; is bound in turn to each possible conditioning case. The conditioning
; cases generated satisify the definition given above, i.e they satisfy
; conditioning-case-p.  Then body is executed with the binding in
; effect, for each such binding.  input-node-list can also be a node
; instead of a node-list. In this case, if the node is a deterministic
; chance node or a value node then the macro ignores the state-labels of
; the node and executes only once with the state in the cond-case bound
; to nil.

; This is the latest of many versions. Runs slightly slower than the fastest version.
; Is more comprehensible.

(defmacro for-all-cond-cases ((case-variable node-list &key (main-node nil)) &body body)
  (let ((template-var (gentemp "template"))(value-var (gentemp "value"))
	(node-list-var (gentemp "node-list"))(special-case-p (gentemp "spl-case-p"))
	(pointer-list (gentemp "pointer-list")))
    `(let* ((,node-list-var ,node-list)
	    ,value-var ,case-variable ,special-case-p ,template-var ,pointer-list)
       (declare (inline special-case-1-p special-case-2-old-syntax-p  rotate-pointer-list
			special-case-2-new-syntax-p prepare-nodes-and-make-template))
	;This cond statement sets the special case flag if necessary and
	; initializes the template-var.
       (cond
	 ((special-case-1-p ,node-list-var)
	  (setq ,special-case-p t ,template-var nil))
	 ((special-case-2-new-syntax-p ,node-list-var)
	  (setq ,special-case-p t ,template-var (list (list ,node-list-var))))
	 ((special-case-2-old-syntax-p ,node-list-var ,main-node)
	  (setq ,special-case-p t ,template-var (list (list (first ,node-list-var)))))
	 (t (setq ,special-case-p nil)
	    (multiple-value-setq (,template-var ,pointer-list)
	      (prepare-nodes-and-make-template ,node-list-var))))
	;The actual loop. There is only one run if special-case-p is true.
       (loop
	; have removed the copy-list around template-var (17 Apr)
	; This increment macro is temporary. Put in to caibrate estimation fns.
	 (INCREMENT-OPERATION-COUNT-IF-UNCHANGED
	   (setq ,case-variable ,template-var ,value-var (progn ,@body)))
	 (if (or ,special-case-p
		 (null (rotate-pointer-list ,pointer-list ,template-var)))
	     (return ,value-var))))))


;-----------------------------------------------------------------------------------------

; Gets a new list consisting of the node-state pairs in cond-case such
; that the nodes in the pairs are mentioned in node-list. This fn was used heavily
; in the earlier version. Is hardly used now due to the emphasis on keeping consing
; down.

(defun find-reqd-nodes&states (cond-case node-list)
  (labels ((find-node-in-cond-case (node)
	     (or (find node cond-case :key #'car)
		 (error "The cond-case ~A does not contain the node ~A that is in the
                         required node-list ~A" cond-case node node-list))))
    (mapcar #'find-node-in-cond-case node-list)))







