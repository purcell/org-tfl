;;; org-tfl --- Transport for London meets Orgmode

;;; Commentary:

;;; Code:
(require 'url)
(require 'json)
(require 'cl-lib)
(require 'helm)
(require 'org)
(require 'org-element)

(defgroup org-tfl nil
  "Org mode Transport for London."
  :group 'org)

(defcustom org-tfl-api-id nil
  "The application id for the Transport for London API."
  :type 'string
  :group 'org-tfl)

(defcustom org-tfl-api-key nil
  "The application key for the Transport for London API."
  :type 'string
  :group 'org-tfl)

(defvar url-http-end-of-headers nil
  "The location in a buffer of a http response that's at the end of headers.")
(defvar org-tfl-api-base-url "https://api.tfl.gov.uk/"
  "The base url to the TFL API.")
(defvar org-tfl-api-jp "Journey/JourneyResults/%s/to/%s"
  "API endpoint for the journey planner.")

;; Journey Planner context
(defvar org-tfl-jp-arg-from nil)
(defvar org-tfl-jp-arg-to nil)
(defvar org-tfl-jp-arg-via nil)
(defvar org-tfl-jp-arg-nationalSearch nil)
(defvar org-tfl-jp-arg-date nil)
(defvar org-tfl-jp-arg-time nil)
(defvar org-tfl-jp-arg-timeIs "Departing")
(defvar org-tfl-jp-arg-journeyPreference "leasttime")
(defvar org-tfl-jp-arg-mode nil)
(defvar org-tfl-jp-arg-accessibilityPreference nil)
(defvar org-tfl-jp-arg-fromName nil)
(defvar org-tfl-jp-arg-toName nil)
(defvar org-tfl-jp-arg-viaName nil)
(defvar org-tfl-jp-arg-maxTransferMinutes nil)
(defvar org-tfl-jp-arg-maxWalkingMinutes nil)
(defvar org-tfl-jp-arg-walkingSpeed "average")
(defvar org-tfl-jp-arg-cyclePreference nil)
(defvar org-tfl-jp-arg-adjustment nil)
(defvar org-tfl-jp-arg-bikeProficiency nil)
(defvar org-tfl-jp-arg-alternativeCycle nil)
(defvar org-tfl-jp-arg-alternativeWalking t)
(defvar org-tfl-jp-arg-applyHtmlMarkup nil)
(defvar org-tfl-jp-arg-useMultiModalCall nil)

;; Disambiguations
(defvar org-tfl-jp-fromdis nil)
(defvar org-tfl-jp-todis nil)
(defvar org-tfl-jp-viadis nil)

(defvar org-tfl-org-buffer nil)
(defvar org-tfl-org-buffer-point nil)

(defvar org-tlf-from-history nil)
(defvar org-tlf-to-history nil)
(defvar org-tlf-via-history nil)


(cl-defun org-tfl-create-icon (path &optional (asc 80) (text "  "))
  "Return string with icon at PATH displayed with ascent ASC and TEXT."
  (propertize text 'display
	      (create-image
	       (with-temp-buffer
		 (insert-file-contents path) (buffer-string))
	       nil t :ascent asc :mask 'heuristic)))

;; Icons
(defconst org-tfl-icon-cam
  (org-tfl-create-icon (concat (file-name-directory load-file-name) "cam.svg")))
(defconst org-tfl-icon-location
  (org-tfl-create-icon (concat (file-name-directory load-file-name) "location.svg")))
(defconst org-tfl-icon-tube
  (org-tfl-create-icon (concat (file-name-directory load-file-name) "tube.svg")))
(defconst org-tfl-icon-overground
  (org-tfl-create-icon (concat (file-name-directory load-file-name) "overground.svg")))
(defconst org-tfl-icon-bus
  (org-tfl-create-icon (concat (file-name-directory load-file-name) "bus.svg")))
(defconst org-tfl-icon-train
  (org-tfl-create-icon (concat (file-name-directory load-file-name) "train.svg")))
(defconst org-tfl-icon-walking
  (org-tfl-create-icon (concat (file-name-directory load-file-name) "walking.svg")))
(defconst org-tfl-icon-dlr
  (org-tfl-create-icon (concat (file-name-directory load-file-name) "dlr.svg")))
(defconst org-tfl-icon-coach
  (org-tfl-create-icon (concat (file-name-directory load-file-name) "coach.svg")))
(defconst org-tfl-icon-river-bus
  (org-tfl-create-icon (concat (file-name-directory load-file-name) "river-bus.svg")))
(defconst org-tfl-icon-replacement-bus
  (org-tfl-create-icon (concat (file-name-directory load-file-name) "replacement-bus.svg")))
(defconst org-tfl-icon-disruption
  (org-tfl-create-icon (concat (file-name-directory load-file-name) "disruption.svg")))

(defvar org-tfl-mode-icons
  (list
   (cons "coach" org-tfl-icon-coach)
   (cons "overground" org-tfl-icon-overground)
   (cons "river-bus" org-tfl-icon-river-bus)
   (cons "dlr" org-tfl-icon-dlr)
   (cons "bus" org-tfl-icon-bus)
   (cons "replacement-bus" org-tfl-icon-replacement-bus)
   (cons "tube" org-tfl-icon-tube)
   (cons "walking" org-tfl-icon-walking)
   (cons "national-rail" org-tfl-icon-train)
   (cons "train" org-tfl-icon-train))
  "Mapping of modes to icons.")

(defface org-tfl-bakerloo-face
  '((t (:foreground "white" :background "#996633")))
  "Bakerloo Line Face"
  :group 'org-tfl)

(defface org-tfl-central-face
  '((t (:foreground "white" :background "#CC3333")))
  "Central Line Face"
  :group 'org-tfl)

(defface org-tfl-circle-face
  '((t (:foreground "white" :background "#FFCC00")))
  "Circle Line Face"
  :group 'org-tfl)

(defface org-tfl-district-face
  '((t (:foreground "white" :background "#006633")))
  "District Line Face"
  :group 'org-tfl)

(defface org-tfl-hammersmith-face
  '((t (:foreground "white" :background "#CC9999")))
  "Hammersmith and City Line Face"
  :group 'org-tfl)

(defface org-tfl-jubliee-face
  '((t (:foreground "white" :background "#868F98")))
  "Jubliee Line Face"
  :group 'org-tfl)

(defface org-tfl-metropolitan-face
  '((t (:foreground "white" :background "#660066")))
  "Metropolitan Line Face"
  :group 'org-tfl)

(defface org-tfl-northern-face
  '((t (:foreground "white" :background "#000000")))
  "Northern Line Face"
  :group 'org-tfl)

(defface org-tfl-piccadilly-face
  '((t (:foreground "white" :background "#000099")))
  "Piccadilly Line Face"
  :group 'org-tfl)

(defface org-tfl-victoria-face
  '((t (:foreground "white" :background "#0099CC")))
  "Victoria Line Face"
  :group 'org-tfl)

(defface org-tfl-waterloo-face
  '((t (:foreground "white" :background "#66CCCC")))
  "Waterloo and City Line Face"
  :group 'org-tfl)

(defvar org-tfl-line-faces
  '(("Bakerloo line" 0 'org-tfl-bakerloo-face prepend)
    ("Central line" 0 'org-tfl-central-face prepend)
    ("Circle line" 0 'org-tfl-circle-face prepend)
    ("District line" 0 'org-tfl-district-face prepend)
    ("Hammersmith and City line" 0 'org-tfl-hammersmith-face prepend)
    ("Jubliee line" 0 'org-tfl-jubliee-face prepend)
    ("Metropolitan line" 0 'org-tfl-metropolitan-face prepend)
    ("Northern line" 0 'org-tfl-northern-face prepend)
    ("Piccadilly line" 0 'org-tfl-piccadilly-face prepend)
    ("Victoria line" 0 'org-tfl-victoria-face prepend)
    ("Waterloo and City line" 0 'org-tfl-waterloo-face prepend))
  "Mapping of lines to faces.")

(defcustom org-tfl-time-format-string "%H:%M"
  "String for 'format-time-string' to display time."
  :type 'string
  :group 'org-tfl)

(defcustom org-tfl-datetime-format-string "%H:%M %d.%m.%Y"
  "String for 'format-time-string' to display date and time."
  :type 'string
  :group 'org-tfl)

(defun org-tfl-get (list &rest keys)
  "Retrieve a value from a LIST with KEYS."
  (let ((list list))
    (while (and list (listp list) keys)
      (setq list (cdr (assoc (car keys) list)))
      (setq keys (cdr keys)))
    (unless keys
      list)))

(defun org-tfl-date-to-time (tfldate)
  "Convert a TFLDATE string of the TFL API to time."
  (string-match "\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)T\\([0-9]\\{2\\}\\):\\([0-9]\\{2\\}\\):\\([0-9]\\{2\\}\\)" tfldate)
  (encode-time
   (string-to-number (match-string 6 tfldate))
   (string-to-number (match-string 5 tfldate))
   (string-to-number (match-string 4 tfldate))
   (string-to-number (match-string 3 tfldate))
   (string-to-number (match-string 2 tfldate))
   (string-to-number (match-string 1 tfldate))))

(defun org-tfl-format-date (tfldate)
  "Format the TFLDATE string.

If it's the same day as today, 'org-tfl-time-format-string' is used.
If the date is another day, 'org-tfl-datetime-format-string' is used."
  (let ((time (org-tfl-date-to-time tfldate)))
    (if (zerop (- (time-to-days time)
		  (time-to-days (current-time))))
	(format-time-string org-tfl-time-format-string time)
      (format-time-string org-tfl-datetime-format-string time))))

(defun org-tfl-jp-format-mode-icons (legs)
  "Return a formatted string with the mode icons for LEGS."
  (mapconcat
   (lambda (leg)
     (or (org-tfl-get org-tfl-mode-icons (org-tfl-get leg 'mode 'id))
	 (org-tfl-get leg 'mode 'id)))
   legs
   " "))

(defun org-tfl-jp-format-leg-disruption-icon (leg)
  "Return a disruption icon if there are disruptions for the given LEG."
  (if (equal (org-tfl-get leg 'isDisrupted) :json-false)
      ""
    (concat org-tfl-icon-disruption " ")))

(defun org-tfl-chop (s len)
  "If S is longer than LEN, wrap the words with newlines."
  (with-temp-buffer
    (insert s)
    (let ((fill-column len))
      (fill-region (point-min) (point-max)))
    (buffer-substring-no-properties (point-min) (point-max))))

(defun org-tfl-jp-format-leg-disruptions (leg level)
  "Return a formatted string with disruptions for the given LEG at 'org-mode' LEVEL."
  (if (equal (cdr (assoc 'isDisrupted leg)) :json-false)
      ""
      (format
       "\n%s Disruptions\n%s"
       (make-string level (string-to-char "*"))
       (mapconcat
	`(lambda (disruption)
	   (format
	    "%s %s\n%s"
	    (make-string ,(+ level 1) (string-to-char "*"))
	    (org-tfl-get disruption 'categoryDescription)
	    (org-tfl-chop (org-tfl-get disruption 'description) ,fill-column)))
	(org-tfl-get leg 'disruptions)
	"\n"))))

(defun org-tfl-jp-format-leg-detailed (leg level)
  "Return a detailed formatted string for the given LEG at the given 'org-mode' LEVEL."
  (format
   "%s %s%s%s"
   (make-string level (string-to-char "*"))
   (org-tfl-jp-format-leg-disruption-icon leg)
   (org-tfl-get leg 'instruction 'detailed)
   (org-tfl-jp-format-leg-disruptions leg (+ level 1))))

(defun org-tfl-jp-format-leg (leg level)
  "Return a formatted string for the given LEG at the given 'org-mode' LEVEL."
  (format
   "%s %3smin %s %s %s%s\n%s"
   (make-string level (string-to-char "*"))
   (org-tfl-get leg 'duration)
   (org-tfl-format-date (org-tfl-get leg 'departureTime))
   (or (org-tfl-get org-tfl-mode-icons (org-tfl-get leg 'mode 'id))
       (org-tfl-get leg 'mode 'id))
   (org-tfl-jp-format-leg-disruption-icon leg)
   (org-tfl-get leg 'instruction 'summary)
   (org-tfl-jp-format-leg-detailed leg (+ level 1))))

(defun org-tfl-jp-format-journey (journey level)
  "Return a formatted string for the given JOURNEY at the given 'org-mode' LEVEL."
  (let ((legs (org-tfl-get journey 'legs)))
    (format
     "%s %4smin %s Departs: %s Arrives: %s\n%s"
     (make-string level (string-to-char "*"))
     (org-tfl-get journey 'duration)
     (org-tfl-jp-format-mode-icons legs)
     (org-tfl-format-date (org-tfl-get journey 'startDateTime))
     (org-tfl-format-date (org-tfl-get journey 'arrivalDateTime))
     (mapconcat `(lambda (leg) (org-tfl-jp-format-leg leg ,(+ level 1)))
		legs
		"\n"))))

(defun org-tfl-jp-format-title (result)
  "Return a formattes string suitable for a title of a Journey Planner RESULT."
  (let ((date (org-tfl-format-date (org-tfl-get result 'searchCriteria 'dateTime)))
	(journey (elt (org-tfl-get result 'journeys) 0)))
    (if journey
      (format
       "%3smin %s Dep.: %s Arr.: %s | %s to %s"
       (org-tfl-get journey 'duration)
       (org-tfl-jp-format-mode-icons (org-tfl-get journey 'legs))
       (org-tfl-format-date (org-tfl-get journey 'startDateTime))
       (org-tfl-format-date (org-tfl-get journey 'arrivalDateTime))
       org-tfl-jp-arg-fromName org-tfl-jp-arg-toName)
      (format "%s to %s (%s): No journeys found!"
	      org-tfl-jp-arg-fromName org-tfl-jp-arg-toName date))))

(defun org-tfl-jp-format-itinerary-result (result level &optional heading)
  "Return a nice formatted string of the given itinerary RESULT.

Heading in the given 'org mode' LEVEL.
No heading if HEADING is nil."
  (concat
   (if heading
       (format
	"%s Itinerary Result from %s to %s%s:\n"
	(make-string level (string-to-char "*"))
	org-tfl-jp-arg-fromName
	org-tfl-jp-arg-toName
	(if org-tfl-jp-arg-viaName
	    (format
	     " via %s"
	     org-tfl-jp-arg-viaName)
	  ""))
     "")
   (mapconcat
    `(lambda (journey) (org-tfl-jp-format-journey journey ,(+ level 1)))
    (org-tfl-get result 'journeys) "\n")))

(defun org-tfl-jp-itinerary-handler (result resulthandler)
  "Let RESULT be handled by RESULTHANDLER."
  (funcall resulthandler result))

(defun org-tfl-jp-itinerary-show-in-buffer (result)
  "Show itinerary RESULT."
  (let ((journeys (org-tfl-get result 'journeys))
	(level (+ (or (org-current-level) 0) 1)))
    (if (zerop (length journeys))
	(message "No journeys found!")
      (let ((buf (get-buffer-create "Itinerary Results")))
	(display-buffer buf)
	(with-current-buffer buf
	  (erase-buffer)
	  (org-mode)
	  (font-lock-add-keywords nil org-tfl-line-faces t)
	  (insert (org-tfl-jp-format-itinerary-result result level t))
	  (hide-sublevels (+ level 1)))))))

(defun org-tfl-jp-replace-link (pos desc)
  "Replace the link description at POS with DESC."
  (goto-char pos)
  (let ((linkregion (org-in-regexp org-bracket-link-regexp 1))
	(link (org-link-unescape (org-match-string-no-properties 1)))
	(properties (org-entry-properties pos 'standard)))
    (delete-region (car linkregion) (cdr linkregion))
    (org-cut-subtree)
    (org-insert-subheading nil)
    (org-promote-subtree)
    (insert (format "[[%s][%s]]" link desc))
    (dolist (prop properties)
      (org-set-property (car prop) (cdr prop)))))

(defun org-tfl-jp-itinerary-insert-org (result)
  "Insert itinerary RESULT in org mode."
  (let ((journeys (org-tfl-get result 'journeys)))
    (display-buffer org-tfl-org-buffer)
    (with-current-buffer org-tfl-org-buffer
      (font-lock-add-keywords nil org-tfl-line-faces t)
      (org-tfl-jp-replace-link org-tfl-org-buffer-point (org-tfl-jp-format-title result))
      (let ((level (+ (or (org-current-level) 0) 1))
	    (element (org-element-at-point)))
	(goto-char (org-element-property :contents-begin element))
	(when (equal (org-element-type (org-element-at-point)) 'property-drawer)
	    (goto-char (org-element-property :end (org-element-at-point))))
	(insert (org-tfl-jp-format-itinerary-result result level nil))
	(goto-char org-tfl-org-buffer-point)
	(hide-sublevels level)))))

(defun org-tfl-jp-get-disambiguations (result)
  "Set the disambiguation options from RESULT."
  (setq org-tfl-jp-fromdis nil
	org-tfl-jp-todis nil
	org-tfl-jp-viadis nil
	org-tfl-jp-fromdis
	(or (org-tfl-get result 'fromLocationDisambiguation 'disambiguationOptions)
	    (eq (org-tfl-get result 'fromLocationDisambiguation 'matchStatus)
		"identified"))
	org-tfl-jp-todis
	(or (org-tfl-get result 'toLocationDisambiguation 'disambiguationOptions)
	    (eq (org-tfl-get result 'toLocationDisambiguation 'matchStatus)
		"identified"))
	org-tfl-jp-viadis
	(or (org-tfl-get result 'viaLocationDisambiguation 'disambiguationOptions)
	    (eq (org-tfl-get result 'viaLocationDisambiguation 'matchStatus)
		"identified"))))

(defun org-tfl-jp-pp-disambiguation (candidate)
  "Nice formatting for disambiguation CANDIDATE."
  (let* ((place (assoc 'place candidate))
	 (type (eval (org-tfl-get place 'placeType)))
	 (modes (org-tfl-get place 'modes))
	 (commonName (org-tfl-get place 'commonName)))
    (cond ((equal type "StopPoint")
	   (if modes
	       (concat (mapconcat
			#'(lambda (mode) (or (org-tfl-get org-tfl-mode-icons mode) mode))
			modes " ")
		       " "
		       commonName)
	     commonName))
	  ((equal type "PointOfInterest")
	   (format "%s %s" org-tfl-icon-cam commonName))
	  ((equal type "Address")
	   (format "%s %s" org-tfl-icon-location commonName))
	  ('t
	   (format "%s: %s" type commonName)))))

(defun org-tfl-jp-transform-disambiguations (candidates)
  "Transform disambiguation option CANDIDATES.

Result is a list of (DISPLAY . REAL) values."
  (mapcar (lambda (cand) (cons (org-tfl-jp-pp-disambiguation cand) cand))
	  candidates))

(defun org-tfl-jp-resolve-helm (cands var commonvar name resulthandler)
  "Let the user select CANDS to set VAR and COMMONVAR.

NAME for the helm section.
Afterwards 'org-tfl-jp-resolve-disambiguation' will be called with RESULTHANDLER."
  (helm
   :sources `(((name . ,name)
	       (candidates . ,(org-tfl-jp-transform-disambiguations (eval cands)))
	       (action . (lambda (option)
			   (setq ,cands nil)
			   (setq ,commonvar (org-tfl-get option 'place 'commonName))
			   (setq ,var (format "%s,%s"
					      (org-tfl-get option 'place 'lat)
					      (org-tfl-get option 'place 'lon)))
			   (org-tfl-jp-resolve-disambiguation ',resulthandler)))))))

(defun org-tfl-jp-resolve-disambiguation (resulthandler)
  "Let the user choose from the disambiguation options.

If there are no options retrieve itinerary and call RESULTHANDLER."
  (cond ((vectorp org-tfl-jp-fromdis)
	 (org-tfl-jp-resolve-helm 'org-tfl-jp-fromdis
				  'org-tfl-jp-arg-from
				  'org-tfl-jp-arg-fromName
				  (format "Select FROM location for %s." org-tfl-jp-arg-from)
				  resulthandler))
	((vectorp org-tfl-jp-todis)
	 (org-tfl-jp-resolve-helm 'org-tfl-jp-todis
				  'org-tfl-jp-arg-to
				  'org-tfl-jp-arg-toName
				  (format "Select TO location for %s." org-tfl-jp-arg-to)
				  resulthandler))
	((vectorp org-tfl-jp-viadis)
	 (org-tfl-jp-resolve-helm 'org-tfl-jp-viadis
				  'org-tfl-jp-arg-via
				  'org-tfl-jp-arg-viaName
				  (format "Select VIA location for %s." org-tfl-jp-arg-via)
				  resulthandler))
	(t
	 (url-retrieve
	  (org-tfl-jp-make-url)
	  `(lambda (status &rest args)
	     (apply 'org-tfl-jp-handle ',resulthandler status args))))))

(defun org-tfl-jp-disambiguation-handler (result resulthandler)
  "Resolve disambiguation of RESULT and try again with RESULTHANDLER."
  (org-tfl-jp-get-disambiguations result)
  (if (and org-tfl-jp-fromdis org-tfl-jp-todis)
      (org-tfl-jp-resolve-disambiguation resulthandler)
    (if org-tfl-jp-fromdis
	(message "Cannot resolve To Location: %s" org-tfl-jp-arg-to)
      (message "Cannot resolve From Location: %s" org-tfl-jp-arg-from))))

(defvar org-tfl-jp-handlers
  `(("Tfl.Api.Presentation.Entities.JourneyPlanner.ItineraryResult, Tfl.Api.Presentation.Entities"
     . org-tfl-jp-itinerary-handler)
    ("Tfl.Api.Presentation.Entities.JourneyPlanner.DisambiguationResult, Tfl.Api.Presentation.Entities"
     . org-tfl-jp-disambiguation-handler)))

(defun org-tfl-jp-make-url ()
  "Create journey planner url.

For keys see 'org-tfl-jp-retrieve'."
  (replace-regexp-in-string
   "&+$" ""
   (concat org-tfl-api-base-url
	   (format org-tfl-api-jp
		   (url-hexify-string org-tfl-jp-arg-from)
		   (url-hexify-string org-tfl-jp-arg-to))
	  "?"
	  (if (and org-tfl-api-jp org-tfl-api-key)
	      (format "app_id=%s&app_key=%s&" (or org-tfl-api-id "") (or org-tfl-api-key ""))
	    "")
	  (if org-tfl-jp-arg-via (format "via=%s&" (url-hexify-string org-tfl-jp-arg-via)) "")
	  (if org-tfl-jp-arg-nationalSearch
	      (format "nationalSearch=%s&" org-tfl-jp-arg-nationalSearch) "")
	  (if org-tfl-jp-arg-date (format "date=%s&" org-tfl-jp-arg-date) "")
	  (if org-tfl-jp-arg-time (format "time=%s&" org-tfl-jp-arg-time) "")
	  (format "timeIs=%s&" org-tfl-jp-arg-timeIs)
	  (format "journeyPreference=%s&" org-tfl-jp-arg-journeyPreference)
	  (if org-tfl-jp-arg-mode (format "mode=%s&" org-tfl-jp-arg-mode) "")
	  (if org-tfl-jp-arg-accessibilityPreference (format "accessibilityPreference=%s&"
					      org-tfl-jp-arg-accessibilityPreference) "")
	  (if org-tfl-jp-arg-fromName
	      (format "fromName=%s&" (url-hexify-string org-tfl-jp-arg-fromName)) "")
	  (if org-tfl-jp-arg-toName
	      (format "toName=%s&" (url-hexify-string org-tfl-jp-arg-toName)) "")
	  (if org-tfl-jp-arg-viaName
	      (format "viaName=%s&" (url-hexify-string org-tfl-jp-arg-viaName)) "")
	  (if org-tfl-jp-arg-maxTransferMinutes
	      (format "maxTransferMinutes=%s&" org-tfl-jp-arg-maxTransferMinutes) "")
	  (if org-tfl-jp-arg-maxWalkingMinutes
	      (format "maxWalkingMinutes=%s&" org-tfl-jp-arg-maxWalkingMinutes) "")
	  (format "average=%s&" org-tfl-jp-arg-walkingSpeed)
	  (if org-tfl-jp-arg-cyclePreference
	      (format "cyclePreference=%s&" org-tfl-jp-arg-cyclePreference) "")
	  (if org-tfl-jp-arg-adjustment (format "adjustment=%s&" org-tfl-jp-arg-adjustment) "")
	  (if org-tfl-jp-arg-bikeProficiency
	      (format "bikeProficiency=%s&" org-tfl-jp-arg-bikeProficiency) "")
	  (if org-tfl-jp-arg-alternativeCycle
	      (format "alternativeCycle=%s&" org-tfl-jp-arg-alternativeCycle) "")
	  (if org-tfl-jp-arg-alternativeWalking
	      (format "alternativeWalking=%s&" org-tfl-jp-arg-alternativeWalking) "")
	  (if org-tfl-jp-arg-applyHtmlMarkup
	      (format "applyHtmlMarkup=%s&" org-tfl-jp-arg-applyHtmlMarkup) "")
	  (if org-tfl-jp-arg-useMultiModalCall
	      (format "useMultiModalCall=%s&" org-tfl-jp-arg-useMultiModalCall) ""))))

(defun org-tfl-jp-handle-error (data response)
  "Handle errors with DATA and RESPONSE."
  (if (eq (nth 1 (car data)) 'http)
      (message "HTTP %s: %s" (nth 2 (car data)) response)))

(defun org-tfl-jp-handle-redirect (data response)
  "Handle redirect errors with DATA and RESPONSE."
  (message "Got redirected. Are you sure you supplied the correct credentials?"))

(defun org-tfl-jp-handle (resulthandler status &rest args)
  "Handle the result of a jp request with RESULTHANDLER.

If status is not successful other handlers are called STATUS.
ARGS are ignored."
  (goto-char url-http-end-of-headers)
  (cond ((eq (car status) :error)
	 (org-tfl-jp-handle-error (cdr status) (buffer-substring (point) (point-max))))
	((eq (car status) :redirect)
	 (org-tfl-jp-handle-redirect (cdr status) (buffer-substring (point) (point-max))))
	(t
	 (let* ((result (json-read))
		(type (org-tfl-get result '$type))
		(handler (org-tfl-get org-tfl-jp-handlers type)))
	   (funcall handler result resulthandler)))))

(cl-defun org-tfl-jp-retrieve
    (from to &key
	  (via nil) (nationalSearch nil) (date nil) (time nil) (timeIs "Departing")
	  (journeyPreference "leasttime") (mode nil) (accessibilityPreference nil)
	  (fromName nil) (toName nil) (viaName nil) (maxTransferMinutes nil)
	  (maxWalkingMinutes nil) (walkingSpeed "average") (cyclePreference nil)
	  (adjustment nil) (bikeProficiency nil) (alternativeCycle nil)
	  (alternativeWalking nil) (applyHtmlMarkup nil) (useMultiModalCall nil)
	  (resulthandler 'org-tfl-jp-itinerary-show-in-buffer))
  "Retrieve journey result FROM TO with PARAMS.

FROM and TO are locations and can be names, Stop-IDs or coordinates of the format
\"lonlat:0.12345,67.890\".
VIA can be an optional place between FROM and TO.
NATIONALSEARCH should be \"True\" for journeys outside London.
DATE of the journey in yyyyMMdd format.
TIME of the journey in HHmm format.
TIMEIS does the given DATE and TIME relate to departure or arrival, e.g.
\"Departing\" | \"Arriving\".
JOURNEYPREFERENCE \"leastinterchange\" | \"leasttime\" | \"leastwalking\".
MODE comma seperated list, possible options \"public-bus,overground,train,tube,coach,dlr,cablecar,tram,river,walking,cycle\".
ACCESSIBILITYPREFERENCE comma seperated list, possible options \"noSolidStairs,noEscalators,noElevators,stepFreeToVehicle,stepFreeToPlatform\".
FROMNAME is the location name associated with a from coordinate.
TONAME is the location name associated with a to coordinate.
VIANAME is the location name associated with a via coordinate.
MAXTRANSFERMINUTES The max walking time in minutes for transfer eg. \"120\".
MAXWALKINGMINUTES The max walking time in minutes for journey eg. \"120\".
WALKINGSPEED \"slow\" | \"average\" | \"fast\".
CYCLEPREFERENCE \"allTheWay\" | \"leaveAtStation\" | \"takeOnTransport\" | \"cycleHire\".
ADJUSTMENT time adjustment command, e.g. \"TripFirst\" | \"TripLast\".
BIKEPROFICIENCY comma seperated list, possible options \"easy,moderate,fast\".
ALTERNATIVECYCLE Option to determine whether to return alternative cycling journey.
ALTERNATIVEWALKING Option to determine whether to return alternative walking journey.
APPLYHTMLMARKUP Flag to determine whether certain text (e.g. walking instructions) should be output with HTML tags or not.
USEMULTIMODALCALL A boolean to indicate whether or not to return 3 public transport journeys, a bus journey, a cycle hire journey, a personal cycle journey and a walking journey.
RESULTHANDLER is the function to call after retrieving the result."
  (setq org-tfl-jp-arg-from from
	org-tfl-jp-arg-to to
	org-tfl-jp-arg-via via
	org-tfl-jp-arg-fromName from
	org-tfl-jp-arg-toName to
	org-tfl-jp-arg-viaName via
	org-tfl-jp-arg-nationalSearch nationalSearch
	org-tfl-jp-arg-date date
	org-tfl-jp-arg-time time
	org-tfl-jp-arg-timeIs timeIs
	org-tfl-jp-arg-journeyPreference journeyPreference
	org-tfl-jp-arg-mode mode
	org-tfl-jp-arg-accessibilityPreference accessibilityPreference
	org-tfl-jp-arg-fromName fromName
	org-tfl-jp-arg-toName toName
	org-tfl-jp-arg-viaName viaName
	org-tfl-jp-arg-maxTransferMinutes maxTransferMinutes
	org-tfl-jp-arg-maxWalkingMinutes maxWalkingMinutes
	org-tfl-jp-arg-walkingSpeed walkingSpeed
	org-tfl-jp-arg-cyclePreference cyclePreference
	org-tfl-jp-arg-adjustment adjustment
	org-tfl-jp-arg-bikeProficiency bikeProficiency
	org-tfl-jp-arg-alternativeCycle alternativeCycle
	org-tfl-jp-arg-alternativeWalking alternativeWalking
	org-tfl-jp-arg-applyHtmlMarkup applyHtmlMarkup
	org-tfl-jp-arg-useMultiModalCall useMultiModalCall

	org-tfl-jp-fromdis nil
	org-tfl-jp-todis nil
	org-tfl-jp-viadis nil)

  (url-retrieve
   (org-tfl-jp-make-url)
   `(lambda (status &rest args)
      (apply 'org-tfl-jp-handle ',resulthandler status args))))

(defun org-tfl-jp (from to via datetime timeIs)
  "Plan journey FROM TO VIA at DATETIME.

TIMEIS if t, DATETIME is the departing time."
  (interactive
   (list (read-from-minibuffer "From: " nil nil nil 'org-tfl-from-history)
	 (read-from-minibuffer "To: " nil nil nil 'org-tfl-to-history)
	 (read-from-minibuffer "Via: " nil nil nil 'org-tfl-via-history)
	 (org-read-date t t)
	 (yes-or-no-p "Time is departure time? No for arrival time:")))
  (let ((date (format-time-string "%Y%m%d" datetime))
	(time (format-time-string "%H%M" datetime))
	(timeis (if timeIs "Departing" "Arriving")))
    (org-tfl-jp-retrieve from to
			 :via (if (equal "" via) nil via)
			 :date date :time time :timeIs timeis)))

(cl-defun org-tfl-jp-retrieve-org (from to &rest keywords &allow-other-keys)
  "Use 'org-tfl-jp-itinerary-insert-org' as handlefunc.

Inserts the result in the current buffer.
For the rest see 'org-tfl-jp-retrieve'."
  (setq org-tfl-org-buffer (current-buffer))
  (setq org-tfl-org-buffer-point (point))
  (apply 'org-tfl-jp-retrieve from to :resulthandler 'org-tfl-jp-itinerary-insert-org keywords))

;; Example calls
;; (add-to-list 'load-path (file-name-directory (buffer-file-name)))
;; (require 'org-tfl)
;; (org-tfl-jp-retrieve "lonlat:\"-0.13500003041,51.50990587838\"" "lonlat:\"-0.29547881328,51.57205666482\"")
;; (org-tfl-jp-retrieve "Piccadilly Circus" "Preston Road")
;; (org-tfl-jp)
;; Example google map
;; http://maps.google.com/maps/api/staticmap?size=400x400&path=color:0xff0000ff|weight:5|51.50995148354,-0.13730392858|51.51005674077,-0.13770314438|51.51037143411,-0.13826675679|51.51069031179,-0.13852757046|51.51103706317,-0.13884489705|51.51127414526,-0.13905140592|51.5114932536,-0.13925864926|51.51160269339,-0.13935507057|51.51208629904,-0.13979653938|51.51239641512,-0.14007214182|51.51239641512,-0.14007214182|51.51252405606,-0.14018223742|51.51307125061,-0.14066437027|51.51314428585,-0.14073345641|51.51370046492,-0.14121523646&markers=color%3ablue|label%3aS|51.51037143411,-0.13826675679|51.51069031179,-0.13852757046&sensor=false

(provide 'org-tfl)
;;; org-tfl ends here
