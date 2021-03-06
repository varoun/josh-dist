;;; -*- Mode: LISP; Syntax: Common-Lisp; Package: Ideal;  Base: 10 -*-

(in-package :ideal)



;;;;********************************************************
;;;;  Copyright (c) 1989, 1992 Rockwell International -- All rights reserved.
;;;;  Rockwell International Science Center Palo Alto Lab
;;;;********************************************************


;;;;;;;;;;;;;;;;;;;;;;;; Sampath ;;;;;;;;;;;;;;;;;;;;



(export '(CREATE-COMPLETE-DIAGRAM
	   CREATE-BELIEF-NET
	   CREATE-NODE-SET
	   CREATE-DISTRIBUTIONS
	   EDIT-DISTRIBUTIONS
	   EDIT-NODE-DISTRIBUTION
	   CREATE-ARCS ))

;--------------------------------------------------------

; Creates whole diagram and returns it.

; If :belief-net is non-nil then all the nodes created are probabilistic
; chance nodes.  If :binary-nodes is non-nil then all the nodes are
; created with 2 states each.  If :binary-state-labels is non-nil it is
; assumed to be a list of desired state-label names. :number of nodes
; when non-nil specifies the number of nodes required in the diagram.

(defun create-complete-diagram (&key number-of-nodes belief-net binary-nodes
				binary-node-labels noisy-or)
  (create-distributions
    (create-arcs
      (create-node-set number-of-nodes belief-net binary-nodes binary-node-labels
		       noisy-or))))

(defun create-belief-net (&key number-of-nodes binary-nodes noisy-or
			  (binary-node-labels '(:TRUE :FALSE)))
  (create-complete-diagram :number-of-nodes number-of-nodes
			   :belief-net t
			   :binary-nodes binary-nodes
			   :binary-node-labels binary-node-labels
			   :noisy-or noisy-or))

;------------------ Creating just nodes -------------------------------------------
; Returns a set of nodes that make up a consistent diagram, albeit with no
; arcs. Use create-arcs to add arcs.

(defun create-node-set (&optional n belief-net binary-nodes binary-node-labels noisy-or
			noisy-or-subtype)
  (let ((diagram nil)
	(number-of-nodes (or n (query 'FIXNUM "How many nodes does the diagram have?"))))
    (dotimes (i number-of-nodes)
      (setq diagram (add-node-interactively
		      diagram
		      :number i 
		      :probabilistic-chance-node belief-net
		      :binary-node binary-nodes
		      :binary-node-labels binary-node-labels
		      :noisy-or noisy-or
		      :noisy-or-subtype noisy-or-subtype)))
    (values diagram)))
    
(defun add-node-interactively (diagram &key number
				  probabilistic-chance-node
				  binary-node
				  binary-node-labels
				  noisy-or noisy-or-subtype)
  (format t "~%*****************Creating Node Number ~D *******************~%" number)
  (let (name type relation-type state-labels)
	; Get the name
    (setq name (query `(and SYMBOL (not (MEMBER ,@(mapcar #'node-name diagram))))
		      "What is the node's name ?"))
	; Get the type (NOISY-OR is given as an option to the user even though it is a subtype)
    (setq type (cond
		 ((or noisy-or probabilistic-chance-node) :CHANCE)
		 (t (query '(MEMBER :chance :decision :value :noisy-or)
			   "What type of node is it ?"))))
	; If the type is :NOISY-OR set necessary flags and values required later
    (when (eq type :NOISY-OR)
      (setq type :CHANCE)
      (setq noisy-or t)
      (setq noisy-or-subtype
	    (cond
	      (binary-node :binary)
	      ((typep noisy-or-subtype '(MEMBER :binary :nary :generic)) noisy-or-subtype)
	      (t (query '(MEMBER :binary :nary :generic) "What type of Noisy or node ?"))))
      (if (eq noisy-or-subtype :BINARY)
	  (setq binary-node t)))
	; Get relation type (be smart about querying only when necessary)
    (setq relation-type (cond
			  ((or noisy-or probabilistic-chance-node) :PROB)
			  (t (case type
			       ((:decision :value) :det)
			       (t (query '(MEMBER :prob :det) "Is the node probabilistic or ~@
                                                  Deterministic [:prob or :det] ?"))))))
    (when noisy-or
      (if binary-node
	  (format t "~%his is a Binary noisy or node. When inputing a label list, the first ~
                     label in the list will be the FALSE state and the second label will be ~
                      the true state")
	  (format t "~%Noisy or needs ordering of labels. The ordering assumed is `increasing ~
                 from left to right' in the list that you input")))
    (setq state-labels (get-label-names binary-node binary-node-labels))
    (add-node diagram
	      :name name
	      :type type
	      :relation-type relation-type
	      :state-labels state-labels
	      :noisy-or noisy-or
	      :noisy-or-subtype noisy-or-subtype)))

(defun get-label-names (binary-node binary-node-labels)
  (labels ((valid-labels-list-p (label-list &optional length)
	     (and (every #'symbolp label-list)
		  (all-unique-p label-list)
		  (or (null length)
		      (eq length (length label-list))))))
    (when binary-node
      (when binary-node-labels
	(if (valid-labels-list-p binary-node-labels 2)
	    (return-from GET-LABEL-NAMES binary-node-labels)
	    (error "~A is not a valid binary label pair (i.e list of two different symbols)"
		   binary-node-labels)))
      (format t "~%Binary Node: Needs exactly two labels"))
    (let ((label-list nil) (n nil))
      (loop
	(setq label-list (query 'LIST "Type in list of label names"))
	(cond
	  ((and binary-node (not (= (setq n (length label-list)) 2)))
	   (format t "~%Binary node. Needs exactly 2 labels. You have specified ~A. Try again"
		   n))
	  ((not (valid-labels-list-p label-list))
	   (format t "~%The list is not composed of non-repeating symbols. Try again"))
	  (t (return label-list)))))))

;----------- Creating Arcs ------------------------------------------------------------

; Queries and sets the arcs in the diagram.

(defun create-arcs (&optional (diagram *diagram*))
  ; Delete all existing arcs
  (dolist (n diagram)
    (delete-arcs n (node-predecessors n)))
  ; Add arcs interactively
  (dolist (n diagram)
    (add-arcs n (input-valid-pred-list n diagram)))
  (values diagram))

(defun input-valid-pred-list (node diagram)
  (let ((input nil)(bad-names nil))
    (loop
      (setq input (query 'LIST "Enter list of immediate predecessors of the node ~S :"
		   (node-name node)))
      (cond
	((setq bad-names (remove-if #'(lambda (n)(find-node n diagram)) input))
	 (format t "~% The subset ~A of input ~A are not names of nodes in the diagram.~
                       Try again." bad-names input))
	(t (let* ((pred-nodes (mapcar #'(lambda (n)(find-node n diagram)) input))
		  (bad-pred-nodes nil))
	     (cond
	       ((setq bad-pred-nodes
		      (remove-if-not #'(lambda (p)(member node (ancestors p))) pred-nodes))
		(format t "Adding the nodes ~A of the input ~A as predecessors of ~A ~
                            will cause cycles. Try again" bad-pred-nodes input node))
	       (t (return pred-nodes)))))))))


;------ Creating distributions -----------------------------------------------

;; Sets the distributions in the diagram

(defun create-distributions (&optional (diagram *diagram*))
  ; This is a dolist and not a mapc coz MACL 1.3 doesnt like the mapc (27 Feb 90)
  (dolist (n diagram)(create-node-distribution n))
  (values diagram))


(defun create-node-distribution (node)
  (unless (decision-node-p node)
    (format t "~%*******Setting distribution for node ~A. Type : ~A ~
                                        Relation-type :~A*******"
	    node (node-type node) (relation-type node))
    (cond
      ((probabilistic-node-p node)(q&s-dist-prob node))
      ((deterministic-node-p node)(q&s-dist-det node))
      (t (error "Node ~A is not an noisy-or node prob node or det node" node))))
  (values node))

 
(defun edit-distributions (&optional (diagram *diagram*))
  (mapc #'(lambda (node)(edit-node-distribution node)) diagram))

(defun edit-node-distribution (node)
  (cond
    ((decision-node-p node)
     (format t "~%Node ~A is a decision node. No distribution editing required"
	     node))
    ((probabilistic-node-p node)(q&s-dist-prob node))
    ((deterministic-node-p node)(q&s-dist-det node))
    (t (error "Node ~A is not an noisy-or node prob node or det node" node)))
  (values node))

(defun q&s-dist-prob (node)
  (cond
    ((noisy-or-node-p node)
     (ecase (noisy-or-subtype node)
       (:BINARY (q&s-binary-noisy-or node))
       (:NARY (q&s-nary-noisy-or node))
       (:GENERIC (q&s-generic-noisy-or node)))
     (compile-noisy-or-distribution node))
    (t (q&s-dist-generic-prob node))))

;--------  Query for and set the distribution for noisy-or nodes.
;

(defun q&s-generic-noisy-or (node)
  (format t "~% ***** Generic Noisy Or Node ~A *************" (node-name node))
  (format t "~%------- Inhibitor probabilities ------------")
  (dolist (p (node-predecessors node))
    (format t "~%Enter inhibitor probs for predecessor ~A" p)
    (for-all-cond-cases (pred-case p)
      (setf (inhibitor-prob-of node pred-case)
	     (prob-query `(PROBABILITY<= 1) (inhibitor-prob-of node pred-case)
				"~%State: ~A :Enter:"
				(label-name (state-in pred-case))))))
  (format t "~%------- Deterministic Function ------------")
  (for-all-cond-cases (case (node-predecessors node))
    (setf (noisy-or-det-fn-of node case)
	  (find (prob-query `(MEMBER ,@(mapcar #'label-name (state-labels node)))
			    (noisy-or-det-fn-of node case)
		            "~%Enter ~A"
			    (value-string node case))
		(state-labels node) :key #'label-name)))
  (values nil))


(defun q&s-nary-noisy-or (node)
  (format t "~% ***** Standard Nary Noisy Or Node ~A *************" (node-name node))
  (format t "~%------- Inhibitor probabilities ------------")
  (dolist (p (node-predecessors node))
    (format t "~%Enter inhibitor probs for predecessor ~A" p)
    (for-all-cond-cases (pred-case p)
      (setf (inhibitor-prob-of node pred-case)
	     (prob-query `(PROBABILITY<= 1) (inhibitor-prob-of node pred-case)
				"~%State: ~A :Enter:"
				(label-name (state-in pred-case))))))
  (format t "~%The Deterministic Function for this node is the standard ~
               nary generalized OR function")
  (set-noisy-or-det-fn-to-standard-nary-or-fn node)
  (values nil))


(defun q&s-binary-noisy-or (node)
  (format t "~% *****  Binary Noisy Or Node ~A *************" (node-name node))
  (format t "~%Since this is binary noisy or node, the inhibitor probabilities ~
              for all states but the 'FALSE' state of each predecessor is set to 0")
  (format t "~%------- Inhibitor probabilities ------------")
  (dolist (p (node-predecessors node))
    (for-all-cond-cases (pred-case p)
      (setf (inhibitor-prob-of node pred-case)
	    (cond
	      ((noisy-or-false-case-p pred-case)
	       (prob-query `(PROBABILITY<= 1) (inhibitor-prob-of node pred-case)
			   "~%Predecessor ~A 'False' state ~A :Enter"
			   (node-name p)(label-name (state-in pred-case))))
	      (t 0)))))
  (format t "~%The Deterministic Function for this node is the standard ~
               generalized OR function")
  (set-noisy-or-det-fn-to-standard-nary-or-fn node)
  (values nil))

;--------  Query for and set the distribution for a generic probabilistic node.

(defun q&s-dist-generic-prob (node)
  (for-all-cond-cases (cond-case (node-predecessors node))
    (let ((states (state-labels node)) (total 0) node-case)
      (loop
	(setq node-case (make-conditioning-case (list (cons node (pop states)))))
	(when (null states)
	  (ideal-warning "Last case ~A in this row. ~%Setting it automatically to ~A"
			 (prob-string node-case cond-case) (- 1 total))
	  (setf (prob-of node-case cond-case) (- 1 total))
	  (return))
	(incf total
	      (setf (prob-of node-case cond-case)
		    (prob-query `(PROBABILITY<= ,(- 1 total)) (prob-of node-case cond-case)
				"~%Enter ~A" (prob-string node-case cond-case))))))))

; -------------- Query and set the distribution for a deterministic node

(defun q&s-dist-det (node)
  (case (node-type node)
    (:chance (for-all-cond-cases (case (node-predecessors node))
	       (setf (deterministic-state-of node case)
		     (find (prob-query `(MEMBER ,@(mapcar #'label-name (state-labels node)))
				       (deterministic-state-of node case)
		            "~%Enter ~A"
			    (value-string node case))
			   (state-labels node) :key #'label-name))))
    (:value (for-all-cond-cases (case (node-predecessors node))
	      (setf (deterministic-state-of node case)
		    (prob-query 'NUMBER (deterministic-state-of node case)
					"~%Enter ~A"
					(value-string node case)))))))


; Wont handle reading "nil" properly but its not meant to do read "nil".

(defun prob-query (type-spec old-value &rest format-args)
  (loop
    (terpri)
    (apply #'format (cons *query-io* format-args))
    (format *query-io* "~A  =>"
	    (if old-value (format nil " [Default : ~A]" old-value) ""))
    (let* ((input (read-line *query-io*))
	   (parsed-input (if (equal input "") nil (read-from-string input)))
	   (reqd-input (or parsed-input old-value)))
      (cond
	((typep reqd-input type-spec) (return reqd-input))
	( t (warn "Input ~S is not of type ~S. Try again." reqd-input type-spec))))))










