;;; js-dependency-injector.el --- Inject paths to JS classes

;; Copyright (C) 2014  Dominic Charlesworth <dgc336@gmail.com>

;; Author: Dominic Charlesworth <dgc336@gmail.com>
;; Keywords: convenience, abbrev, tools

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 3
;; of the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package allows you to perform the equivalent of dependency
;; injection for javascript files

;;; Code:

(require 'dash)

(defvar js-inject-use-projectile nil
  "Whether or not to use the projectile project files when searching for dependency.")
(when (require 'projectile nil 'noerror)
  (setq js-inject-use-projectile t))

;;; Group Definitions
(defgroup js-injector nil
  "Manage the minor mode to allow javascript injection."
  :group 'tools
  :group 'convenience)

(defvar js-inject-use-dev-dependencies nil)

(defcustom js-injector-keymap-prefix (kbd "C-c C-j")
  "Js-Injector keymap prefix."
  :group 'js-injector
  :type 'key-sequence)

(defun sort-dependencies ()
  "Sort the dependency require paths alphabetically.
This reorders the class list to align with the reordered
require paths."
  (interactive)
  (save-excursion
    (let ((require-class-alist '())
          (class-name-list (get-class-name-list))
          (require-path-list (get-require-path-list)))
      (mapc #'(lambda (require-path)
                (push (list (format "%s" require-path) (pop class-name-list)) require-class-alist))
            require-path-list)
      (setq require-class-alist
            (sort require-class-alist #'(lambda (a b) (string< (car a) (car b)))))

      (setq require-path-list
            (mapcar #'(lambda (x) (car x)) require-class-alist))
      (setq class-name-list
            (mapcar #'(lambda (x) (cadr x)) require-class-alist))

      (inject-dependency require-path-list class-name-list t))))

;; Main function definitions
(defun get-node-modules ()
  "Get a list of node packages defined in package.json."
  (let ((package-json (locate-dominating-file
                       (file-name-directory (buffer-file-name))
                       "package.json")))
    (when package-json
      (let* ((json-object-type 'hash-table)
             (json-contents (with-temp-buffer
                              (insert-file-contents
                               (format "%s/package.json" package-json))
                              (buffer-string)))
             (json-hash (json-read-from-string json-contents))
             (result (list)))
        (mapc
         (lambda (arg)
           (maphash
            (lambda (key value) (setq result (-distinct (append result (list key)))))
            (gethash arg json-hash)))
         (-non-nil (list
                    "dependencies"
                    (when js-inject-use-dev-dependencies "devDependencies"))))
        result))))

(defun require-node-module-at-point ()
  "Inject a node modules defined in package.json at point.
This will search up from the current directory to find the package.json and
pull out the dependencies - by default this will just use DEPENDENCIES, but can
also use DEVDEPENDENCIES - and then prompt the user for the module they want
to include."
  (interactive)
  (save-excursion
    (let* ((popup-point (point))
           (node-modules (get-node-modules)))
      (if node-modules
          (let ((result (completing-read "Require Node Module:" node-modules))
                (quote-char (get-quote-char)))
            (insert (format "var %s = require(%s%s%s);"
                            (sanitise result) quote-char result quote-char)))
        (message "No node modules found in current project")))))

(defun require-relative-module-at-point ()
  "Inject a module relative to the current file from a project."
  (interactive)
  (let* ((qc (get-quote-char))
         (modules (--filter (string-match "\.js$" (cadr it))
                            (--map (cons (file-name-sans-extension (car it)) (cdr it)) projectable-file-alist)))
         (module (ido-completing-read "Require: " modules))
         (relative-modules (--map (file-relative-name it (file-name-directory (buffer-file-name))) (cdr (assoc module modules))))
         (relative-module (if (> (length relative-modules) 1)
                              (ido-completing-read "Module: " relative-modules)
                            (car relative-modules)))
         (result (file-name-sans-extension (if (string-match "^[a-zA-Z]" relative-module) (concat "./" relative-module) relative-module))))
    (insert (format "var %s = require(%s%s%s);" (sanitise module) qc result qc ))))

(defun sanitise (s)
  "Return a sanitised string S."
  (with-temp-buffer
    (insert s)
    (goto-char (point-min))
    (while (re-search-forward "-\\(.\\)" nil t)
      (replace-match (capitalize (match-string 1))))
    (buffer-string)))

(defun require-dependency-at-point ()
  "Inject the dependency at point.
This function will take the word under point and look for it in the
dependncy list.  If it exists, it will add a require path as the variable argument"
  (interactive)
  (save-excursion
    (let* ((popup-point (point))
           (class-symbol (or (thing-at-point 'word)
                             (save-excursion (backward-word) (thing-at-point 'word))))
           (class-name (concat class-symbol ".js"))
           (result (assoc class-name (get-dependency-relative-alist)))
           (qc (get-quote-char))
           (bounds (or (bounds-of-thing-at-point 'word)
                       (save-excursion (backward-word) (bounds-of-thing-at-point 'word))))
           (bound-start (car bounds))
           (bound-end (cdr bounds)))
      (if result
          (let ((require-path (show-popup-with-options result popup-point "%s")))
            (when (and
                 (string-match "['\"]" (buffer-substring bound-end (+ bound-end 1)))
                 (string-match "['\"]" (buffer-substring bound-start (- bound-start 1))))
              (setq bound-start (- bound-start 1))
              (setq bound-end (+ bound-end 1)))
            (replace-region bound-start bound-end (format "%s%s%s" qc (file-name-sans-extension require-path) qc)))
        (message "%s does not exist in any dependencies" class-symbol)))))

(defun inject-dependency-at-point ()
  "Inject the dependency at point.
This function will take the word under point and look for it in the
dependncy list.  If it exists, it will append it to the function list
and add the require path, if it is already used it will update the
current dependency.  If it does not exist, do nothing and print to the
minibuffer."
  (interactive)
  (save-excursion
    (let* ((popup-point (point))
           (class-symbol (or (thing-at-point 'word) (save-excursion (backward-word) (thing-at-point 'word))))
           (class-name (concat (downcase class-symbol) ".js"))
           (result (assoc class-name (get-dependency-alist)))
           (qc (get-quote-char)))
      (if result
          (let ((require-path (show-popup-with-options result popup-point (concat qc "%s"qc ))))
            (inject-dependency (list require-path) (list class-symbol)))
        (message "%s does not exist in any dependencies" class-symbol)))))

(defun update-dependencies ()
  "Update all of the classes in the function block.
This function constructs a list of require paths based on the class
names present in the function block.  These are delegated to the
inject-dependency function which will replace the view with the new
arguments."
  (interactive)
  (save-excursion
    (let* ((popup-point (point))
           (class-name-list (get-class-name-list))
           (require-path-list (list))
           (dependency-alist (get-dependency-alist)))

      (mapc
       #'(lambda (class-symbol)
           (let* ((class-name (concat (downcase class-symbol) ".js"))
                  (result (assoc class-name dependency-alist))
                  (qc (get-quote-char)))
             (setq require-path-list
                   (append require-path-list
                           (list (if result
                                     (show-popup-with-options result popup-point (concat qc "%s" qc))
                                   (format "\"???/%s\"" (downcase class-symbol))))))))
       class-name-list)
      (inject-dependency require-path-list class-name-list t)
      (sort-dependencies))))

(defun inject-dependency (require-paths class-names &optional replace)
  "Inject or replace a list of REQUIRE-PATHS & CLASS-NAMES into a JS file.
It uses the CLASS-NAMES as the keys of the REQUIRE-PATHS.
The REPLACE flag will replace all require paths and class names with these."
    (let ((require-path-list nil)
          (class-name-list nil)
          (require-path-region (get-require-path-region))
          (class-name-region (get-class-name-region)))
      (when (not replace)
        (setq require-path-list (get-require-path-list))
        (setq class-name-list (get-class-name-list)))
      (mapc
       #'(lambda (require-path)
           (let* ((index (position require-path require-paths :test #'string-equal))
                  (class-name (nth index class-names)))

             (if (not (member class-name class-name-list))
                 (setq class-name-list (append class-name-list (list class-name))))

             (setq index (position class-name class-name-list :test #'string-equal))
             (if (or replace (eq index (length require-path-list)))
                 (setq require-path-list (append require-path-list (list require-path)))
               (setf (nth index require-path-list) require-path))
             ))
       require-paths)

      (replace-region (car class-name-region) (cadr class-name-region)
                      (format-text-in-rectangle (mapconcat 'identity class-name-list ", ") 150))
      (replace-region (car require-path-region) (cadr require-path-region)
                      (format "%s\n" (mapconcat 'identity require-path-list ",\n")))
      (indent-require-block)))

(defun get-dependency-alist ()
  "Construct the dependency alist from the projectable-project-alist.
It assossciates each file name to a list of locations of that file."
    (let ((dependency-alist (list)))
      (mapc
       #'(lambda (project-assoc)
           (mapc
            #'(lambda (elt)
                ;; Filter results by /script/ regexp
                (let* ((filtered-results (filter-list (lambda (x) (string-match "/script/" x)) (cdr elt))))
                  ;; If we have filtered results, append them
                  (when filtered-results
                    (let ((modified-results
                           (mapcar #'(lambda (x)
                                       (concat (replace-regexp-in-string ".*script" (car project-assoc) (file-name-directory x))
                                               (replace-regexp-in-string ".js" "" (car elt)))) filtered-results)))
                      ;; Create alist element of file to folder
                      (let ((appended-results (append (list (car elt)) modified-results)))

                        ;; If entry already exists - remove and redefine appended-results
                        (when (not (eq nil (assoc (car elt) dependency-alist)))
                          (setq appended-results (append (assoc (car elt) dependency-alist) modified-results))
                          (setq dependency-alist (delq (assoc (car elt) dependency-alist) dependency-alist)))

                        (push appended-results dependency-alist))))
                  ))
            (cdr project-assoc)))
       projectable-project-alist) dependency-alist))

(defun get-dependency-relative-alist ()
  "Constructs the dependency alist from projectable-project-alist.
It assosciates each file name to a list of relative file paths"
  (let ((dependency-alist (list)))
    (mapc
     #'(lambda (project-assoc)
         (mapc
          #'(lambda (elt)
              (let* ((cwd (file-name-directory (buffer-file-name)))
                     (modified-results
                      (mapcar #'(lambda (x)
                                (let ((relative-name (file-relative-name x cwd)))
                                  (if (string-match "^[a-zA-Z]" relative-name)
                                      (concat "./" relative-name)
                                    relative-name)))
                            (cdr elt))))
                (let ((appended-results (append (list (car elt)) modified-results)))

                  ;; If entry already exists - remove and redefine appended-results
                  (when (not (eq nil (assoc (car elt) dependency-alist)))
                    (setq appended-results (append (assoc (car elt) dependency-alist) modified-results))
                    (setq dependency-alist (delq (assoc (car elt) dependency-alist) dependency-alist)))

                  (push appended-results dependency-alist))
                )
              ) (cdr project-assoc))
         ) projectable-project-alist) dependency-alist)
  )

(defun get-require-path-list ()
  "Get the list of current require paths."
  (let ((a (car (get-require-path-region)))
        (b (cadr (get-require-path-region))))
    (mapcar #'chomp (split-string (buffer-substring a b) ",\\s-*\n\\s-*"))))

(defun get-class-name-list  ()
  "Get the list of the mapped class names."
  (let ((a (car (get-class-name-region)))
        (b (cadr (get-class-name-region))))
    (if (not (eq a b))
        (mapcar #'chomp (split-string (buffer-substring a b) ",\\s-*"))
      nil)))

(defun chomp (str)
  "Chomp leading and tailing whitespace from STR."
  (replace-regexp-in-string (rx (or (: bos (* (any " \t\n")))
                                    (: (* (any " \t\n")) eos)))
                            ""
                            str))

(defun get-require-path-region ()
  "Get the region containing the require block."
  (get-region "\\s-*\\[\n\\s-*" "\\s-*\\]"))

(defun get-class-name-region ()
  "Get the region containing the list of class names."
  (get-region "function\s-*\(" "\)"))

(defun get-region (regex-a regex-b)
  "Get a region based on starting from REGEX-A to REGEX-B."
  (goto-char (point-min))
  (if (search-forward-regexp "require\\|define" nil t)
      (let ((start (search-forward-regexp regex-a))
            (end (- (search-forward-regexp regex-b) 1)))
        (list start end))
    (error "Could not find beginning of a require block")))

(defun get-quote-char ()
  "Get the majority quote character used in a file."
  (if (> (count-matches "\"" (point-min) (point-max))
         (count-matches "'" (point-min) (point-max)))
      "\"" "'"))

(defun filter-list (condp lst)
  "Filter using CONDP function call mapped to LST."
  (delq nil (mapcar (lambda (x) (and (funcall condp x) x)) lst)))

(defun show-popup-with-options (options popup-point f)
  "Show a popup with OPTIONS at POPUP-POINT with format F."
  (format f (if (= 1 (length (cdr options)))
                (cadr options)
              (popup-menu* (cdr options) :point popup-point))))

(defun indent-require-block ()
  "Indent the block containing require paths."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (indent-region (search-forward-regexp "function\\s-*(.*\n") (cadr (get-class-name-region)))
    (indent-region (car (get-require-path-region)) (cadr (get-require-path-region)))
    (goto-char (cadr (get-require-path-region))) (indent-according-to-mode)))

(defun replace-region (region-start region-end replacement)
  "Replace a region from REGION-START to REGION-END with REPLACEMENT string."
  (goto-char region-start)
  (delete-region region-start region-end)
  (insert replacement))

(defun format-text-in-rectangle (text width)
  "Wrap a block of TEXT with a maximum WIDTH and indent."
  (with-temp-buffer
    (insert text)
    (goto-char (+ (point-min) width))
    (while (< (point) (point-max))
      (backward-word)
      (newline)
      (goto-char (+ (point) width)))
    (format "%s" (buffer-substring (point-min) (point-max)))))

(defun format-region-in-rectangle (b e)
  (interactive "r")
  (replace-region b e (format-text-in-rectangle (buffer-substring b e) 120)))

(defvar js-injector-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "i") #'inject-dependency-at-point)
    (define-key map (kbd "r") #'require-dependency-at-point)
    (define-key map (kbd "C-r") #'require-node-module-at-point)
    (define-key map (kbd "s") #'sort-dependencies)
    (define-key map (kbd "u") #'update-dependencies)
    (define-key map (kbd "l") #'indent-require-block)
    map)
  "Keymap for Js-Injector commands after `js-injector-keymap-prefix'.")
(fset 'js-injector-command-map js-injector-command-map)

(defvar js-injector-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map js-injector-keymap-prefix 'js-injector-command-map)
    map)
  "Keymap for Projectile mode.")

(define-minor-mode js-injector-minor-mode
  "Minor mode to help with js dependency injection.

When called interactively, toggle `js-injectorminor-mode'.  With prefix
ARG, enable `js-injectorminor-mode' if ARG is positive, otherwise disable
it.

When called from Lisp, enable `js-injectorminor-mode' if ARG is omitted,
nil or positive.  If ARG is `toggle', toggle `js-injectorminor-mode'.
Otherwise behave as if called interactively.

\\{projectile-mode-map}"
  :lighter "js-i"
  :keymap js-injector-mode-map
  :group 'js-injector
  :require 'js-injector)

(provide 'js-dependency-injector)
;;; js-dependency-injector.el ends here
