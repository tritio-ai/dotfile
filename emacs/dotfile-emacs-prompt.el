;;; dotfile-emacs-prompt.el --- Public prompt template helper -*- lexical-binding: t; -*-

;;; Commentary:
;; Select an Org-backed prompt template, fill placeholders, preview the result,
;; and copy it to the kill ring/system selection.  This file is intentionally
;; self-contained and does not read private local prompt files.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defgroup dotfile-emacs-prompt nil
  "Reusable public prompt templates."
  :group 'convenience
  :prefix "dotfile-emacs-prompt-")

(defconst dotfile-emacs-prompt--module-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory containing this module.")

(defcustom dotfile-emacs-prompt-file
  (expand-file-name "prompts.org" dotfile-emacs-prompt--module-dir)
  "Org file that stores prompt templates for `dotfile-emacs-prompt-copy'."
  :type 'file
  :group 'dotfile-emacs-prompt)

(defcustom dotfile-emacs-prompt-default-template "codex-implement"
  "Template key used by `dotfile-emacs-prompt-copy-default'."
  :type 'string
  :group 'dotfile-emacs-prompt)

(defcustom dotfile-emacs-prompt-edit-title "Prompt Templates"
  "Org title that enables `dotfile-emacs-prompt-edit-mode'."
  :type 'string
  :group 'dotfile-emacs-prompt)

(defvar dotfile-emacs-prompt-last-rendered nil
  "Last rendered prompt text.")

(defvar dotfile-emacs-prompt--template-history nil
  "Minibuffer history for prompt template selection.")

(defvar dotfile-emacs-prompt-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c i") #'dotfile-emacs-prompt-edit-insert-template)
    map)
  "Keymap for `dotfile-emacs-prompt-edit-mode'.")

(defconst dotfile-emacs-prompt-edit-font-lock-keywords
  `((,(rx "{{" (* space)
          (group (or "case" "when"))
          (+ space)
          (group (+? (not (any "}"))))
          (* space) "}}")
     (1 font-lock-keyword-face append)
     (2 font-lock-constant-face append))
    (,(rx "{{" (* space) (group "end") (* space) "}}")
     (1 font-lock-keyword-face append))
    (,(rx "{{" (* space)
          (group (seq (any alpha "_") (* (any alnum "_-"))))
          (* space) "}}")
     (1 font-lock-variable-name-face append)))
  "Font-lock rules for public prompt placeholders.")

(defun dotfile-emacs-prompt--normalize-key (title)
  "Return a stable template key from TITLE."
  (replace-regexp-in-string
   "-+" "-"
   (string-trim
    (downcase
     (replace-regexp-in-string "[^[:alnum:]]+" "-" title)))
   t t))

(defun dotfile-emacs-prompt--project-name ()
  "Return the best available project name for prompt variables."
  (let* ((root (or (when (require 'project nil t)
                     (when-let* ((project (project-current nil)))
                       (if (fboundp 'project-root)
                           (project-root project)
                         (car (project-roots project)))))
                   (when (fboundp 'vc-root-dir)
                     (vc-root-dir))
                   default-directory))
         (dir (directory-file-name (expand-file-name root))))
    (file-name-nondirectory dir)))

(defun dotfile-emacs-prompt--split-heading-body (text)
  "Return cons of property alist and body from heading TEXT."
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (let (properties)
      (when (looking-at-p "^[ \t]*:PROPERTIES:[ \t]*$")
        (forward-line 1)
        (while (looking-at "^[ \t]*:\([^: \t\n]+\):[ \t]*\(.*\)$")
          (push (cons (upcase (match-string-no-properties 1))
                      (string-trim (match-string-no-properties 2)))
                properties)
          (forward-line 1))
        (when (looking-at-p "^[ \t]*:END:[ \t]*$")
          (forward-line 1)))
      (cons (nreverse properties)
            (string-trim-right
             (buffer-substring-no-properties (point) (point-max)))))))

(defun dotfile-emacs-prompt--template-label (template)
  "Return completion label for TEMPLATE."
  (let ((key (plist-get template :key))
        (title (plist-get template :title))
        (description (plist-get template :description)))
    (string-trim
     (format "%s  %s%s"
             key
             (or title "")
             (if (string-empty-p (or description ""))
                 ""
               (format " -- %s" description))))))

(defun dotfile-emacs-prompt--read-templates ()
  "Read prompt templates from `dotfile-emacs-prompt-file'."
  (let ((file (expand-file-name dotfile-emacs-prompt-file)))
    (unless (file-readable-p file)
      (user-error "Prompt file not found: %s" file))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (let (templates)
        (while (re-search-forward "^\\* \\(.+\\)$" nil t)
          (let* ((title (string-trim (match-string-no-properties 1)))
                 (body-start (line-beginning-position 2))
                 (body-end (save-excursion
                             (if (re-search-forward "^\\* " nil t)
                                 (match-beginning 0)
                               (point-max))))
                 (parts (dotfile-emacs-prompt--split-heading-body
                         (buffer-substring-no-properties body-start body-end)))
                 (properties (car parts))
                 (body (cdr parts))
                 (key (or (cdr (assoc "KEY" properties))
                          (dotfile-emacs-prompt--normalize-key title)))
                 (description (or (cdr (assoc "DESCRIPTION" properties)) "")))
            (unless (or (string-empty-p title)
                        (string-empty-p body))
              (push (list :key key
                          :title title
                          :description description
                          :body body)
                    templates))))
        (nreverse templates)))))

(defun dotfile-emacs-prompt--read-template ()
  "Read and return a prompt template."
  (let* ((templates (dotfile-emacs-prompt--read-templates))
         (choices (mapcar (lambda (template)
                            (cons (dotfile-emacs-prompt--template-label template)
                                  template))
                          (sort templates
                                (lambda (a b)
                                  (string< (plist-get a :key)
                                           (plist-get b :key))))))
         (selection (completing-read "Prompt template: "
                                     choices nil t nil
                                     'dotfile-emacs-prompt--template-history)))
    (cdr (assoc selection choices))))

(defun dotfile-emacs-prompt--template-by-key (key)
  "Return template identified by KEY."
  (or (cl-find key (dotfile-emacs-prompt--read-templates)
               :key (lambda (template)
                      (plist-get template :key))
               :test #'string=)
      (error "Unknown prompt template: %s" key)))

(defun dotfile-emacs-prompt--placeholder-names (template)
  "Return ordered unique placeholder names from TEMPLATE."
  (let (names)
    (with-temp-buffer
      (insert template)
      (goto-char (point-min))
      (while (re-search-forward
              "{{[ \t\n]*\\([[:alnum:]_-]+\\)[ \t\n]*}}" nil t)
        (let ((name (match-string-no-properties 1)))
          (unless (member name names)
            (push name names)))))
    (nreverse names)))

(defun dotfile-emacs-prompt--history-symbol (name)
  "Return the minibuffer history symbol used for argument NAME."
  (intern (format "dotfile-emacs-prompt--history-%s" name)))

(defun dotfile-emacs-prompt--default-value (name)
  "Return default prompt value for NAME."
  (if (string= name "project")
      (dotfile-emacs-prompt--project-name)
    (let* ((history-symbol (dotfile-emacs-prompt--history-symbol name))
           (history (and (boundp history-symbol)
                         (symbol-value history-symbol))))
      (car history))))

(defun dotfile-emacs-prompt--read-argument (name)
  "Read template argument NAME with its own history default."
  (let* ((history-symbol (dotfile-emacs-prompt--history-symbol name))
         (default (dotfile-emacs-prompt--default-value name))
         (prompt (if (and (stringp default) (not (string-empty-p default)))
                     (format "%s (%s): " name default)
                   (format "%s: " name)))
         (value (read-string prompt nil history-symbol default)))
    (cons name value)))

(defun dotfile-emacs-prompt--read-choice (name choices)
  "Read template argument NAME from CHOICES."
  (let* ((history-symbol (dotfile-emacs-prompt--history-symbol name))
         (history (and (boundp history-symbol)
                       (symbol-value history-symbol)))
         (history-default (cl-find-if (lambda (value) (member value choices))
                                      history))
         (default (or history-default (car choices)))
         (prompt (if (and (stringp default) (not (string-empty-p default)))
                     (format "%s (%s): " name default)
                   (format "%s: " name)))
         (value (completing-read prompt choices nil t nil history-symbol default)))
    (cons name value)))

(defun dotfile-emacs-prompt--control-directive (line)
  "Return control directive from LINE, or nil."
  (when (string-match
         "\\`[ \t]*{{[ \t]*\\(case\\|when\\|end\\)\\(?:[ \t]+\\([^}]+?\\)\\)?[ \t]*}}[ \t]*\\'"
         line)
    (cons (match-string 1 line)
          (when (match-string 2 line)
            (string-trim (match-string 2 line))))))

(defun dotfile-emacs-prompt--case-branch-end (lines start)
  "Return index of the next top-level when/end directive after START in LINES."
  (let ((index start)
        (depth 0)
        found)
    (while (and (< index (length lines)) (not found))
      (let ((directive (dotfile-emacs-prompt--control-directive
                        (nth index lines))))
        (cond
         ((and (= depth 0) directive (member (car directive) '("when" "end")))
          (setq found index))
         ((and directive (string= (car directive) "case"))
          (setq depth (1+ depth)
                index (1+ index)))
         ((and directive (string= (car directive) "end") (> depth 0))
          (setq depth (1- depth)
                index (1+ index)))
         (t
          (setq index (1+ index))))))
    (or found index)))

(defun dotfile-emacs-prompt--collect-case-branches (lines start)
  "Collect case branches in LINES beginning after START."
  (let ((index start)
        branches
        done)
    (while (and (< index (length lines)) (not done))
      (let ((directive (dotfile-emacs-prompt--control-directive
                        (nth index lines))))
        (cond
         ((and directive (string= (car directive) "when"))
          (unless (cdr directive)
            (error "Prompt case branch missing when value"))
          (let ((end (dotfile-emacs-prompt--case-branch-end lines (1+ index))))
            (push (cons (cdr directive)
                        (cl-subseq lines (1+ index) end))
                  branches)
            (setq index end)))
         ((and directive (string= (car directive) "end"))
          (setq done t
                index (1+ index)))
         (t
          (error "Prompt case expected {{when ...}} or {{end}}")))))
    (unless done
      (error "Prompt case missing {{end}}"))
    (list :branches (nreverse branches) :end-index index)))

(defun dotfile-emacs-prompt--resolve-case-lines (lines &optional vars)
  "Resolve case branches in LINES and return cons of text and VARS."
  (let ((index 0)
        output)
    (while (< index (length lines))
      (let* ((line (nth index lines))
             (directive (dotfile-emacs-prompt--control-directive line)))
        (cond
         ((and directive (string= (car directive) "case"))
          (unless (cdr directive)
            (error "Prompt case missing argument name"))
          (let* ((case-name (cdr directive))
                 (collected (dotfile-emacs-prompt--collect-case-branches
                             lines (1+ index)))
                 (branches (plist-get collected :branches))
                 (choices (mapcar #'car branches))
                 (choice (dotfile-emacs-prompt--read-choice case-name choices))
                 (selected (cdr (assoc (cdr choice) branches)))
                 (resolved (dotfile-emacs-prompt--resolve-case-lines
                            selected (cons choice vars))))
            (push (car resolved) output)
            (setq vars (cdr resolved)
                  index (plist-get collected :end-index))))
         ((and directive (member (car directive) '("when" "end")))
          (error "Prompt %s without matching {{case ...}}" (car directive)))
         (t
          (push line output)
          (setq index (1+ index))))))
    (cons (string-join (nreverse output) "\n") vars)))

(defun dotfile-emacs-prompt--resolve-cases (template)
  "Resolve case branches in TEMPLATE."
  (dotfile-emacs-prompt--resolve-case-lines (split-string template "\n")))

(defun dotfile-emacs-prompt--render-string (template vars)
  "Render TEMPLATE string with VARS."
  (let ((result template))
    (dolist (var vars result)
      (setq result
            (replace-regexp-in-string
             (format "{{[ \t\n]*%s[ \t\n]*}}" (regexp-quote (car var)))
             (lambda (_) (cdr var))
             result t t)))))

(defun dotfile-emacs-prompt--render-template (template)
  "Render TEMPLATE, prompting for its variables."
  (let* ((resolved (dotfile-emacs-prompt--resolve-cases
                    (plist-get template :body)))
         (body (car resolved))
         (vars (cdr resolved))
         (existing-names (mapcar #'car vars))
         (missing-names (cl-remove-if
                         (lambda (name) (member name existing-names))
                         (dotfile-emacs-prompt--placeholder-names body)))
         (all-vars (append vars
                           (mapcar #'dotfile-emacs-prompt--read-argument
                                   missing-names))))
    (dotfile-emacs-prompt--render-string body all-vars)))

(defun dotfile-emacs-prompt--copy-to-pasteboard (text)
  "Copy TEXT to kill ring, clipboard, and primary selection when available."
  (kill-new text)
  (when (fboundp 'gui-set-selection)
    (ignore-errors (gui-set-selection 'CLIPBOARD text))
    (ignore-errors (gui-set-selection 'PRIMARY text)))
  (when (fboundp 'x-set-selection)
    (ignore-errors (x-set-selection 'CLIPBOARD text))
    (ignore-errors (x-set-selection 'PRIMARY text)))
  text)

(defun dotfile-emacs-prompt--preview (text)
  "Show TEXT in a prompt preview buffer."
  (let ((buffer (get-buffer-create "*Prompt Preview*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text)
        (goto-char (point-min))
        (special-mode)))
    (display-buffer buffer)))

;;;###autoload
(defun dotfile-emacs-prompt-copy (&optional template-key)
  "Pick TEMPLATE-KEY, render it, preview it, and copy it."
  (interactive)
  (let* ((template (if template-key
                       (dotfile-emacs-prompt--template-by-key template-key)
                     (dotfile-emacs-prompt--read-template)))
         (text (dotfile-emacs-prompt--render-template template)))
    (setq dotfile-emacs-prompt-last-rendered text)
    (dotfile-emacs-prompt--preview text)
    (dotfile-emacs-prompt--copy-to-pasteboard text)
    (message "Copied prompt: %s" (plist-get template :key))))

;;;###autoload
(defun dotfile-emacs-prompt-copy-default ()
  "Render and copy `dotfile-emacs-prompt-default-template'."
  (interactive)
  (dotfile-emacs-prompt-copy dotfile-emacs-prompt-default-template))

;;;###autoload
(defun dotfile-emacs-prompt-copy-last ()
  "Copy the last rendered prompt again."
  (interactive)
  (unless dotfile-emacs-prompt-last-rendered
    (user-error "No prompt has been rendered yet"))
  (dotfile-emacs-prompt--copy-to-pasteboard dotfile-emacs-prompt-last-rendered)
  (message "Copied last prompt"))

;;;###autoload
(defun dotfile-emacs-prompt-bridge-primary-to-pasteboard ()
  "Copy the X PRIMARY selection into the normal pasteboard."
  (interactive)
  (let ((text (or (when (fboundp 'gui-get-selection)
                    (or (ignore-errors (gui-get-selection 'PRIMARY 'STRING))
                        (ignore-errors (gui-get-selection 'PRIMARY 'UTF8_STRING))))
                  (when (fboundp 'x-get-selection)
                    (or (ignore-errors (x-get-selection 'PRIMARY 'STRING))
                        (ignore-errors (x-get-selection 'PRIMARY 'UTF8_STRING)))))))
    (unless (and (stringp text) (not (string-empty-p text)))
      (user-error "PRIMARY selection is empty"))
    (dotfile-emacs-prompt--copy-to-pasteboard text)
    (message "Copied PRIMARY selection to pasteboard")))

(defun dotfile-emacs-prompt-edit--enable-font-lock ()
  "Add prompt template syntax highlighting."
  (font-lock-add-keywords nil dotfile-emacs-prompt-edit-font-lock-keywords 'append)
  (when (fboundp 'font-lock-flush)
    (font-lock-flush)))

(defun dotfile-emacs-prompt-edit--disable-font-lock ()
  "Remove prompt template syntax highlighting."
  (font-lock-remove-keywords nil dotfile-emacs-prompt-edit-font-lock-keywords)
  (when (fboundp 'font-lock-flush)
    (font-lock-flush)))

(defun dotfile-emacs-prompt-edit--title-buffer-p ()
  "Return non-nil when the current buffer declares the prompt template title."
  (save-excursion
    (goto-char (point-min))
    (let ((limit (save-excursion
                   (or (re-search-forward "^\\*" nil t)
                       (point-max)))))
      (catch 'found
        (while (re-search-forward "^[ \t]*#\\+TITLE:[ \t]*\\(.+?\\)[ \t]*$"
                                  limit t)
          (when (string= (string-trim (match-string-no-properties 1))
                         dotfile-emacs-prompt-edit-title)
            (throw 'found t)))
        nil))))

(defun dotfile-emacs-prompt-edit--maybe-enable ()
  "Enable prompt editing mode for the public prompt template file."
  (when (and (derived-mode-p 'org-mode)
             (dotfile-emacs-prompt-edit--title-buffer-p))
    (dotfile-emacs-prompt-edit-mode 1)))

(defun dotfile-emacs-prompt-edit--insert-template-boundary ()
  "Move point to a clean prompt template insertion boundary."
  (unless (bolp)
    (insert "\n"))
  (unless (or (bobp)
              (save-excursion
                (forward-line -1)
                (looking-at-p "[ \t]*$")))
    (insert "\n")))

;;;###autoload
(defun dotfile-emacs-prompt-edit-insert-template ()
  "Insert a new prompt template skeleton."
  (interactive)
  (let* ((title (read-string "Prompt title: "))
         (key (read-string "Prompt key: " nil nil
                           (dotfile-emacs-prompt--normalize-key title)))
         (description (read-string "Description: ")))
    (dotfile-emacs-prompt-edit--insert-template-boundary)
    (insert (format "* %s\n" title))
    (insert ":PROPERTIES:\n")
    (insert (format ":KEY: %s\n" key))
    (insert (format ":DESCRIPTION: %s\n" description))
    (insert ":END:\n")
    (insert "Project: {{project}}\n\nTask:\n{{task}}\n\nInstructions:\n")))

;;;###autoload
(define-minor-mode dotfile-emacs-prompt-edit-mode
  "Minor mode for editing public prompt template Org files."
  :lighter " Prompt"
  :keymap dotfile-emacs-prompt-edit-mode-map
  (if dotfile-emacs-prompt-edit-mode
      (dotfile-emacs-prompt-edit--enable-font-lock)
    (dotfile-emacs-prompt-edit--disable-font-lock)))

(add-hook 'find-file-hook #'dotfile-emacs-prompt-edit--maybe-enable)

(provide 'dotfile-emacs-prompt)
;;; dotfile-emacs-prompt.el ends here
