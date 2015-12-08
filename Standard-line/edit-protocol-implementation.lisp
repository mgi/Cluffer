(cl:in-package #:cluffer-standard-line)

(defmethod cluffer:item-count ((line open-line))
  (- (length (contents line)) (- (gap-end line) (gap-start line))))

(defmethod cluffer:item-count ((line closed-line))
  (length (contents line)))

(defun make-empty-line ()
  (make-instance 'open-line
    :cursors '()
    :contents (make-array 32 :initial-element 0)
    :gap-start 0
    :gap-end 32))
    
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on ITEMS.

;;; When the items of an open line are asked for, we first close the
;;; line.  While this way of doing it might seem wasteful, it probably
;;; is not that bad.  When the items are asked for, the reason is
;;; probably that those items are going to be displayed or used to
;;; drive a parser, or something else that will imply some significant
;;; work for each item.  So even if the line is repeatedly opened (to
;;; edit) and closed (to display), it probably does not matter much.
;;; A slight improvement could be to leave the line open and return a
;;; freshly allocated vector with the items in it.
(defmethod cluffer:items ((line open-line) &key (start 0) (end nil))
  (close-line line)
  (cluffer:items line :start start :end end))

;;; When all the items are asked for, we do not allocate a fresh
;;; vector.  This means that client code is not allowed to mutate the
;;; return value of this function
(defmethod cluffer:items ((line closed-line) &key (start 0) (end nil))
  (if (and (= start 0) (null end))
      (contents line)
      (subseq (contents line) start end)))

(defgeneric close-cursor (cursor))

(defmethod close-cursor ((cursor open-left-sticky-cursor))
  (change-class cursor 'closed-left-sticky-cursor))
  
(defmethod close-cursor ((cursor open-right-sticky-cursor))
  (change-class cursor 'closed-right-sticky-cursor))

(defgeneric close-line (line))

(defmethod close-line ((line closed-line))
  nil)

(defmethod close-line ((line open-line))
  (mapc #'close-cursor (cursors line))
  (let* ((item-count (cluffer:item-count line))
	 (contents (contents line))
	 (new-contents (make-array item-count)))
    (replace new-contents contents
	     :start1 0 :start2 0 :end2 (gap-start line))
    (replace new-contents contents
	     :start1 (gap-start line) :start2 (gap-end line))
    (change-class line 'closed-line
		  :contents new-contents)
    nil))

(defgeneric open-cursor (cursor))

(defmethod open-cursor ((cursor closed-left-sticky-cursor))
  (change-class cursor 'open-left-sticky-cursor))
  
(defmethod open-cursor ((cursor closed-right-sticky-cursor))
  (change-class cursor 'open-right-sticky-cursor))

(defgeneric open-line (line))

(defmethod open-line ((line open-line))
  nil)

(defmethod open-line ((line closed-line))
  (mapc #'open-cursor (cursors line))
  (let* ((contents (contents line))
	 (item-count (length contents))
	 (new-length (max 32 item-count))
	 (new-contents (make-array new-length)))
    (replace new-contents contents
	     :start1 (- new-length item-count) :start2 0)
    (change-class line 'open-line
		  :contents new-contents
		  :gap-start 0
		  :gap-end (- new-length item-count))
    nil))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Detaching and attaching a cursor.

(defmethod cluffer:attach-cursor
    ((cursor attached-cursor) line &optional position)
  (declare (ignore line position))
  (error 'cluffer:cursor-attached))

(defmethod cluffer:attach-cursor
    ((cursor detached-left-sticky-cursor)
     (line open-line)
     &optional
       (position 0))
  (when (> position (cluffer:item-count line))
    (error 'cluffer:end-of-line))
  (push cursor (cursors line))
  (change-class cursor 'open-left-sticky-cursor
		:line line
		:cursor-position position)
  nil)

(defmethod cluffer:attach-cursor
    ((cursor detached-left-sticky-cursor)
     (line closed-line)
     &optional
       (position 0))
  (when (> position (cluffer:item-count line))
    (error 'cluffer:end-of-line))
  (push cursor (cursors line))
  (change-class cursor 'closed-left-sticky-cursor
		:line line
		:cursor-position position)
  nil)
  
(defmethod cluffer:attach-cursor
    ((cursor detached-right-sticky-cursor)
     (line open-line)
     &optional
       (position 0))
  (when (> position (cluffer:item-count line))
    (error 'cluffer:end-of-line))
  (push cursor (cursors line))
  (change-class cursor 'open-right-sticky-cursor
		:line line
		:cursor-position position)
  nil)

(defmethod cluffer:attach-cursor
    ((cursor detached-right-sticky-cursor)
     (line closed-line)
     &optional
       (position 0))
  (when (> position (cluffer:item-count line))
    (error 'cluffer:end-of-line))
  (push cursor (cursors line))
  (change-class cursor 'closed-right-sticky-cursor
		:line line
		:cursor-position position)
  nil)

(defmethod cluffer:detach-cursor
    ((cursor detached-cursor))
  (error 'cluffer:cursor-detached))

(defmethod cluffer:detach-cursor
  ((cursor left-sticky-mixin))
  (setf (cursors (cluffer:line cursor))
	(remove cursor (cursors (cluffer:line cursor))))
  (change-class cursor 'detached-left-sticky-cursor)
  nil)

(defmethod cluffer:detach-cursor
  ((cursor cluffer:right-sticky-mixin))
  (setf (cursors (cluffer:line cursor))
	(remove cursor (cursors (cluffer:line cursor))))
  (change-class cursor 'detached-right-sticky-cursor)
  nil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Operations on cursors.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on BEGINNING-OF-LINE-P.
;;;
;;; Given a cursor, return true if and only if it is at the beginning
;;; of the line.

(defmethod cluffer:beginning-of-line-p
    ((cursor detached-cursor))
  (error 'cluffer:cursor-detached))

;;; The default method just calls CURSOR-POSITION and returns true if
;;; and only if that position is 0.
(defmethod cluffer:beginning-of-line-p
    ((cursor attached-cursor))
  (zerop (cluffer:cursor-position cursor)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on END-OF-LINE-P.

(defmethod cluffer:end-of-line-p
    ((cursor detached-cursor))
  (error 'cluffer:cursor-detached))

;;; The default method just calls CURSOR-POSITION and returns true if
;;; and only if that position is the same as the number of items in
;;; the line.
(defmethod cluffer:end-of-line-p
    ((cursor attached-cursor))
  (= (cluffer:cursor-position cursor)
     (cluffer:item-count (cluffer:line cursor))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on INSERT-ITEM.

(defmethod cluffer:insert-item ((cursor closed-cursor-mixin) item)
  (open-line (cluffer:line cursor))
  (cluffer:insert-item cursor item))

(defmethod cluffer:insert-item ((cursor open-cursor-mixin) item)
  (let* ((pos (cluffer:cursor-position cursor))
	 (line (cluffer:line cursor))
	 (contents (contents line)))
    (cond ((= (gap-start line) (gap-end line))
	   (let* ((new-length (* 2 (length contents)))
		  (diff (- new-length (length contents)))
		  (new-contents (make-array new-length)))
	     (replace new-contents contents
		      :start2 0 :start1 0 :end2 pos)
	     (replace new-contents contents
		      :start2 pos :start1 (+ pos diff))
	     (setf (gap-start line) pos)
	     (setf (gap-end line) (+ pos diff))
	     (setf (contents line) new-contents)))
	  ((< pos (gap-start line))
	   (decf (gap-end line) (- (gap-start line) pos))
	   (replace contents contents
		    :start2 pos :end2 (gap-start line)
		    :start1 (gap-end line))
	   (setf (gap-start line) pos))
	  ((> pos (gap-start line))
	   (replace contents contents
		    :start2 (gap-end line)
		    :start1 (gap-start line) :end1 pos)
	   (incf (gap-end line) (- pos (gap-start line)))
	   (setf (gap-start line) pos))
	  (t
	   nil))
    (setf (aref (contents line) (gap-start line)) item)
    (incf (gap-start line))
    (loop for cursor in (cursors line)
	  do (when (or (and (typep cursor 'cluffer:right-sticky-mixin)
			    (>= (cluffer:cursor-position cursor) pos))
		       (and (typep cursor 'left-sticky-mixin)
			    (> (cluffer:cursor-position cursor) pos)))
	       (incf (cluffer:cursor-position cursor)))))
  nil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on DELETE-ITEM.

(defmethod cluffer:delete-item ((cursor closed-cursor-mixin))
  (open-line (cluffer:line cursor))
  (cluffer:delete-item cursor))

(defmethod cluffer:delete-item ((cursor open-cursor-mixin))
  (when (cluffer:end-of-line-p cursor)
    (error 'cluffer:end-of-line))
  (let* ((pos (cluffer:cursor-position cursor))
	 (line (cluffer:line cursor))
	 (contents (contents line)))
    (cond ((< pos (gap-start line))
	   (decf (gap-end line) (- (gap-start line) pos))
	   (replace contents contents
		    :start2 pos :end2 (gap-start line)
		    :start1 (gap-end line))
	   (setf (gap-start line) pos))
	  ((> pos (gap-start line))
	   (replace contents contents
		    :start2 (gap-end line)
		    :start1 (gap-start line) :end1 pos)
	   (incf (gap-end line) (- pos (gap-start line)))
	   (setf (gap-start line) pos))
	  (t
	   nil))
    (setf (aref contents (gap-end line)) 0)  ; for the GC
    (incf (gap-end line))
    (when (and (> (length contents) 32)
	       (> (- (gap-end line) (gap-start line))
		  (* 3/4 (length contents))))
      (let* ((new-length (floor (length contents) 2))
	     (diff (- (length contents) new-length))
	     (new-contents (make-array new-length)))
	(replace new-contents contents
		 :start2 0 :start1 0 :end2 (gap-start line))
	(replace new-contents contents
		 :start2 (gap-end line) :start1 (- (gap-end line) diff))
	(decf (gap-end line) diff)
	(setf (contents line) new-contents)))
    (loop for cursor in (cursors line)
	  do (when (> (cluffer:cursor-position cursor) pos)
	       (decf (cluffer:cursor-position cursor)))))
  nil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on ERASE-ITEM.

(defmethod cluffer:erase-item ((cursor closed-cursor-mixin))
  (open-line (cluffer:line cursor))
  (cluffer:erase-item cursor))

(defmethod cluffer:erase-item ((cursor open-cursor-mixin))
  (when (cluffer:beginning-of-line-p cursor)
    (error 'cluffer:beginning-of-line))
  (cluffer:backward-item cursor)
  (cluffer:delete-item cursor)
  nil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on FORWARD-ITEM

;;; No need to open the line just because the cursor moves.  
(defmethod cluffer:forward-item ((cursor closed-cursor-mixin))
  (when (cluffer:end-of-line-p cursor)
    (error 'cluffer:end-of-line))
  (incf (cluffer:cursor-position cursor))
  nil)

(defmethod cluffer:forward-item ((cursor open-cursor-mixin))
  (when (cluffer:end-of-line-p cursor)
    (error 'cluffer:end-of-line))
  (incf (cluffer:cursor-position cursor))
  nil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on BACKWARD-ITEM

;;; No need to open the line just because the cursor moves.  
(defmethod cluffer:backward-item ((cursor closed-cursor-mixin))
  (when (cluffer:beginning-of-line-p cursor)
    (error 'cluffer:beginning-of-line))
  (decf (cluffer:cursor-position cursor))
  nil)

(defmethod cluffer:backward-item ((cursor open-cursor-mixin))
  (when (cluffer:beginning-of-line-p cursor)
    (error 'cluffer:beginning-of-line))
  (decf (cluffer:cursor-position cursor))
  nil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on BEGINNING-OF-LINE.
;;;
;;; Position the cursor at the beginning of the line.

(defmethod cluffer:beginning-of-line
    ((cursor detached-cursor))
  (error 'cluffer:cursor-detached))

(defmethod cluffer:beginning-of-line
    ((cursor attached-cursor))
  (setf (cluffer:cursor-position cursor) 0))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on END-OF-LINE.
;;;
;;; Position the cursor at the end of the line.

(defmethod cluffer:end-of-line
    ((cursor detached-cursor))
  (error 'cluffer:cursor-detached))

(defmethod cluffer:end-of-line
    ((cursor attached-cursor))
  (setf (cluffer:cursor-position cursor)
	(cluffer:item-count (cluffer:line cursor))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on ITEM-BEFORE-CURSOR.

;;; No need to open the line.
(defmethod cluffer:item-before-cursor
    ((cursor closed-cursor-mixin))
  (when (cluffer:beginning-of-line-p cursor)
    (error 'cluffer:beginning-of-line))
  (aref (contents (cluffer:line cursor))
	(1- (cluffer:cursor-position cursor))))

(defmethod cluffer:item-before-cursor
    ((cursor open-left-sticky-cursor))
  (when (cluffer:beginning-of-line-p cursor)
    (error 'cluffer:beginning-of-line))
  (let ((pos (1- (cluffer:cursor-position cursor)))
	(line (cluffer:line cursor)))
    (aref (contents line)
	  (if (< pos (gap-start line))
	      pos
	      (+ pos (- (gap-end line) (gap-start line)))))))

(defmethod cluffer:item-before-cursor
    ((cursor open-right-sticky-cursor))
  (when (cluffer:beginning-of-line-p cursor)
    (error 'cluffer:beginning-of-line))
  (let ((pos (1- (cluffer:cursor-position cursor)))
	(line (cluffer:line cursor)))
    (aref (contents line)
	  (if (< pos (gap-start line))
	      pos
	      (+ pos (- (gap-end line) (gap-start line)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on ITEM-AFTER-CURSOR.

;;; No need to open the line.
(defmethod cluffer:item-after-cursor
    ((cursor closed-cursor-mixin))
  (when (cluffer:beginning-of-line-p cursor)
    (error 'cluffer:beginning-of-line))
  (aref (contents (cluffer:line cursor))
	(cluffer:cursor-position cursor)))

(defmethod cluffer:item-after-cursor
    ((cursor open-left-sticky-cursor))
  (when (cluffer:beginning-of-line-p cursor)
    (error 'cluffer:beginning-of-line))
  (let ((pos (cluffer:cursor-position cursor))
	(line (cluffer:line cursor)))
    (aref (contents line)
	  (if (< pos (gap-start line))
	      pos
	      (+ pos (- (gap-end line) (gap-start line)))))))

(defmethod cluffer:item-after-cursor
    ((cursor open-right-sticky-cursor))
  (when (cluffer:beginning-of-line-p cursor)
    (error 'cluffer:beginning-of-line))
  (let ((pos (cluffer:cursor-position cursor))
	(line (cluffer:line cursor)))
    (aref (contents line)
	  (if (< pos (gap-start line))
	      pos
	      (+ pos (- (gap-end line) (gap-start line)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on LINE-SPLIT-LINE.

(defmethod cluffer:line-split-line ((cursor closed-cursor-mixin))
  (let* ((pos (cluffer:cursor-position cursor))
	 (line (cluffer:line cursor))
	 (contents (contents line))
	 (new-contents (subseq contents pos))
	 (new-line (make-instance 'closed-line
		     :cursors '()
		     :contents new-contents)))
    (setf (contents line)
	  (subseq (contents line) 0 pos))
    (setf (cursors new-line)
	  (loop for cursor in (cursors line)
		when (or (and (typep cursor 'cluffer:right-sticky-mixin)
			      (>= (cluffer:cursor-position cursor) pos))
			 (and (typep cursor 'left-sticky-mixin)
			      (> (cluffer:cursor-position cursor) pos)))
		  collect cursor))
    (loop for cursor in (cursors new-line)
	  do (setf (cluffer:line cursor) new-line)
	     (decf (cluffer:cursor-position cursor) pos))
    (setf (cursors line)
	  (set-difference (cursors line) (cursors new-line)))
    new-line))

(defmethod cluffer:line-split-line ((cursor open-cursor-mixin))
  (close-line (cluffer:line cursor))
  (cluffer:line-split-line cursor))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on LINE-JOIN-LINE.

(defmethod cluffer:line-join-line ((line1 open-line) line2)
  (close-line line1)
  (cluffer:line-join-line line1 line2))

(defmethod cluffer:line-join-line (line1 (line2 open-line))
  (close-line line2)
  (cluffer:line-join-line line1 line2))

(defmethod cluffer:line-join-line ((line1 closed-line) (line2 closed-line))
  (loop with length = (length (contents line1))
	for cursor in (cursors line2)
	do (setf (cluffer:line cursor) line1)
	   (incf (cluffer:cursor-position cursor) length))
  (setf (contents line1)
	(concatenate 'vector (contents line1) (contents line2)))
  nil)