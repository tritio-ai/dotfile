;;; legacy-compat.el --- Safe public compatibility features -*- lexical-binding: t; -*-

;;; Commentary:
;; Public, package-light compatibility layer for useful features from the old
;; startup.  Private vault bindings remain owned by the vault configuration.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(defvar dotfile-emacs-state-dir
  (expand-file-name "dotfile-emacs" user-emacs-directory))

;; Backup and history policy -------------------------------------------------
(defconst dotfile-emacs-legacy-backup-dir
  (expand-file-name "backups" dotfile-emacs-state-dir))
(defconst dotfile-emacs-legacy-auto-save-dir
  (expand-file-name "auto-save-list" dotfile-emacs-state-dir))
(make-directory dotfile-emacs-legacy-backup-dir t)
(make-directory dotfile-emacs-legacy-auto-save-dir t)
(setq backup-directory-alist `(("." . ,dotfile-emacs-legacy-backup-dir))
      backup-by-copying t
      version-control t
      delete-old-versions t
      kept-new-versions 6
      kept-old-versions 2
      auto-save-default t
      auto-save-timeout 20
      auto-save-interval 200
      auto-save-file-name-transforms
      `((".*" ,(file-name-as-directory dotfile-emacs-legacy-auto-save-dir) t)))
(setq bookmark-save-flag 1
      recentf-max-saved-items 100
      recentf-max-menu-items 25
      recentf-auto-cleanup 'never
      history-length 1000
      history-delete-duplicates t
      kill-ring-max 1000
      savehist-additional-variables '(kill-ring search-ring regexp-search-ring))
(when (fboundp 'recentf-save-list)
  (run-at-time 300 300 #'recentf-save-list))
(when (require 'semantic nil t)
  (semantic-mode 1))

(setq-default global-auto-revert-non-file-buffers t
              scroll-margin 0
              scroll-conservatively 101
              scroll-preserve-screen-position t
              mode-line-format
              (append '((:eval (format "[%d] " (point))))
                      (default-value 'mode-line-format)))
(when (fboundp 'global-auto-revert-mode) (global-auto-revert-mode 1))
(setq show-paren-delay 0
      show-paren-style 'mixed
      show-paren-when-point-inside-paren t
      show-paren-when-point-in-periphery t)
(show-paren-mode 1)

;; Startup performance -------------------------------------------------------
(defvar dotfile-emacs-gc-normal-threshold (* 16 1024 1024))
(setq read-process-output-max (* 1024 1024)
      fast-but-imprecise-scrolling t
      jit-lock-defer-time 0)
(run-with-idle-timer 5 t #'garbage-collect)
(add-hook 'minibuffer-setup-hook
          (lambda () (setq gc-cons-threshold most-positive-fixnum)))
(add-hook 'minibuffer-exit-hook
          (lambda () (setq gc-cons-threshold dotfile-emacs-gc-normal-threshold)))
(when (and (fboundp 'native-comp-available-p) (native-comp-available-p))
  (setq native-comp-async-report-warnings-errors nil
        native-comp-jit-compilation t))

;; Greek input ---------------------------------------------------------------
(defconst dotfile-emacs-legacy-greek-letters
  '(("a" . "alpha") ("b" . "beta") ("g" . "gamma") ("d" . "delta")
    ("e" . "epsilon") ("z" . "zeta") ("h" . "eta") ("q" . "theta")
    ("i" . "iota") ("k" . "kappa") ("l" . "lambda") ("m" . "mu")
    ("n" . "nu") ("x" . "xi") ("o" . "omicron") ("p" . "pi")
    ("r" . "rho") ("s" . "sigma") ("t" . "tau") ("u" . "upsilon")
    ("f" . "phi") ("c" . "chi") ("y" . "psi") ("w" . "omega")))
(defun dotfile-emacs-legacy-insert-greek ()
  "Insert a Greek letter chosen by completion or send it to a terminal."
  (interactive)
  (let* ((choice (completing-read "Greek letter: "
                                  (mapcar #'cdr dotfile-emacs-legacy-greek-letters)
                                  nil t))
         (capital (y-or-n-p "Capital letter? "))
         (char (char-from-name (format "GREEK %s LETTER %s"
                                       (if capital "CAPITAL" "SMALL")
                                       (upcase choice)))))
    (if (derived-mode-p 'term-mode 'eat-mode)
        (let ((process (get-buffer-process (current-buffer))))
          (if process
              (process-send-string process (char-to-string char))
            (insert char)))
      (insert char))))
(global-set-key (kbd "C-c g") #'dotfile-emacs-legacy-insert-greek)
(with-eval-after-load 'eat
  (dolist (map-symbol '(eat-mode-map eat-semi-char-mode-map eat-line-mode-map
                         eat-emacs-mode-map))
    (when (boundp map-symbol)
      (define-key (symbol-value map-symbol) (kbd "C-c g")
        #'dotfile-emacs-legacy-insert-greek))))

;; Key chords (vendored locally; no network dependency) ---------------------
(when (require 'key-chord nil t)
  (setq key-chord-typing-detection t)
  (key-chord-mode 1)
  (key-chord-define-global ",." "<>\C-b")
  (key-chord-define-global "''" "`'\C-b")
  (key-chord-define-global "hh" #'dotfile-emacs-goto-char-backward))

(defun dotfile-emacs-goto-char-backward (char)
  "Move backward to the previous occurrence of CHAR on this line."
  (interactive "cBackward to character: ")
  (search-backward (char-to-string char) (line-beginning-position) t)
  (forward-char))

;; Window numbering ----------------------------------------------------------
(defun dotfile-emacs-window-number (window)
  (cl-position window (window-list (window-frame window) nil nil)))
(defun dotfile-emacs-select-window-number (number &optional delete)
  (interactive "nWindow number: \nP")
  (let ((window (nth number (window-list nil nil nil))))
    (if (window-live-p window)
        (if delete (delete-window window) (select-window window))
      (user-error "No window numbered %d" number))))
(dotimes (i 9)
  (let ((n i))
    (global-set-key (kbd (format "C-c %d" n))
                    (lambda (&optional arg)
                      (interactive "P")
                      (dotfile-emacs-select-window-number n arg)))))
(defun dotfile-emacs-window-number-mode-line ()
  (format "[%d] " (or (dotfile-emacs-window-number (selected-window)) 0)))
(setq-default mode-line-format
              (append '((:eval (dotfile-emacs-window-number-mode-line)))
                      (default-value 'mode-line-format)))

;; Dired and terminal helpers ------------------------------------------------
(defun dotfile-emacs-dired-copy-content ()
  (interactive)
  (let ((file (dired-get-file-for-visit)))
    (unless (file-regular-p file) (user-error "Not a regular file"))
    (kill-new (with-temp-buffer (insert-file-contents file) (buffer-string)))
    (message "Copied %s" (file-name-nondirectory file))))
(defun dotfile-emacs-dired-find-files (regexp)
  (interactive "sFind files (regexp): ")
  (find-name-dired (dired-current-directory) regexp))
(defun dotfile-emacs-dired-open-eww ()
  "Open the file at point in EWW."
  (interactive)
  (eww-open-file (dired-get-file-for-visit)))
(with-eval-after-load 'dired
  (define-key dired-mode-map (kbd "b") #'dotfile-emacs-dired-copy-content)
  (define-key dired-mode-map (kbd "F") #'dotfile-emacs-dired-find-files)
  (define-key dired-mode-map (kbd "o") #'dotfile-emacs-dired-open-eww)
  (setq dired-listing-switches "-Alht")
  (when (boundp 'dired-kill-when-opening-new-dired-buffer)
    (setq dired-kill-when-opening-new-dired-buffer t)))

(defun dotfile-emacs-send-region-to-terminal ()
  (interactive)
  (let ((text (if (use-region-p)
                  (buffer-substring-no-properties (region-beginning) (region-end))
                (buffer-substring-no-properties (line-beginning-position)
                                                (line-end-position))))
        (buffer (or (get-buffer "*eat*") (get-buffer "*ansi-term*"))))
    (unless buffer (user-error "No Eat or ANSI-term buffer"))
    (with-current-buffer buffer
      (let ((process (get-buffer-process buffer)))
        (unless process (user-error "Terminal process is not running"))
        (process-send-string process (concat text "\n"))))))
(defun dotfile-emacs-term-clear ()
  "Clear an ANSI-term buffer and send a form-feed to its process."
  (interactive)
  (let ((inhibit-read-only t)) (erase-buffer))
  (when-let ((process (get-buffer-process (current-buffer))))
    (process-send-string process "\f")))
(global-set-key (kbd "C-c T") #'dotfile-emacs-send-region-to-terminal)
(with-eval-after-load 'term
  (define-key term-raw-map (kbd "C-c l") #'dotfile-emacs-term-clear)
  (define-key term-raw-map (kbd "C-c C-j") #'term-line-mode)
  (define-key term-raw-map (kbd "C-c g") #'dotfile-emacs-legacy-insert-greek))

;; Emacs Lisp editing shortcuts ---------------------------------------------
(add-hook 'emacs-lisp-mode-hook
          (lambda ()
            (local-set-key (kbd "C-c r") #'eval-region)
            (local-set-key (kbd "C-c f") #'eval-defun)
            (local-set-key (kbd "C-c e") #'eval-last-sexp)
            (local-set-key (kbd "C-c j") #'eval-print-last-sexp)
            (local-set-key (kbd "C-c b") #'eval-buffer)))

;; Smart compile/run and project prefix -------------------------------------
(defun dotfile-emacs-detect-language ()
  (cond ((not buffer-file-name) nil)
        ((string-match-p "\\.py\\'" buffer-file-name) 'python)
        ((string-match-p "\\.rs\\'" buffer-file-name) 'rust)
        ((string-match-p "\\.go\\'" buffer-file-name) 'go)
        ((string-match-p "\\.js\\'" buffer-file-name) 'javascript)
        ((string-match-p "\\.\\(c\\|cc\\|cpp\\)\\'" buffer-file-name) 'c)
        ((string-match-p "\\.\\(el\\|lisp\\|cl\\)\\'" buffer-file-name) 'lisp)))
(defun dotfile-emacs-smart-compile ()
  (interactive)
  (let ((cmd (or (and compile-command
                       (not (string-empty-p compile-command))
                       (not (string= compile-command "make -k"))
                       compile-command)
                 (and (file-exists-p "Makefile") "make")
                 (pcase (dotfile-emacs-detect-language)
                   ('python (format "python3 %s" (file-name-nondirectory buffer-file-name)))
                   ('rust "cargo build") ('go "go build")
                   ('javascript (format "node %s" (file-name-nondirectory buffer-file-name)))
                   ('c (format "gcc -Wall %s -o %s" (file-name-nondirectory buffer-file-name)
                               (file-name-sans-extension (file-name-nondirectory buffer-file-name))))
                   (_ "make -k")))))
    (setq compile-command (read-string "Compile command: " cmd))
    (compile compile-command)))
(defun dotfile-emacs-smart-recompile () (interactive) (recompile))
(defvar dotfile-emacs-shell-command-history nil)
(defun dotfile-emacs-shell-command ()
  "Run a shell command with a persistent in-session history."
  (interactive)
  (let ((command (read-shell-command "Shell command: " nil
                                     'dotfile-emacs-shell-command-history)))
    (shell-command command)))
(defun dotfile-emacs-async-shell-command ()
  "Run an asynchronous shell command with history."
  (interactive)
  (let ((command (read-shell-command "Async shell command: " nil
                                     'dotfile-emacs-shell-command-history)))
    (async-shell-command command)))
(defun dotfile-emacs-replace-in-files (directory pattern old-string new-string)
  "Replace OLD-STRING in files matching PATTERN below DIRECTORY."
  (interactive "DDirectory: \nsFile pattern: \nsOld text: \nsNew text: ")
  (dolist (file (directory-files-recursively directory pattern))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (while (search-forward old-string nil t) (replace-match new-string nil t))
      (write-region (point-min) (point-max) file))))
(defun dotfile-emacs-init-project-from-template (template target project-name)
  "Copy TEMPLATE directory to TARGET and replace PROJECT_NAME placeholders."
  (interactive "DTemplate directory: \nDTarget directory: \nsProject name: ")
  (when (file-exists-p target) (user-error "Target already exists: %s" target))
  (copy-directory template target t t t)
  (dotfile-emacs-replace-in-files target ".*" "{{PROJECT_NAME}}" project-name)
  (message "Project initialized: %s" target))
(global-set-key (kbd "C-c #") #'dotfile-emacs-shell-command)
(global-set-key (kbd "C-c $") #'dotfile-emacs-async-shell-command)
(define-prefix-command 'dotfile-emacs-project-prefix-map)
(global-set-key (kbd "C-c p") #'dotfile-emacs-project-prefix-map)
(dolist (binding '(("f" . project-find-file) ("p" . project-switch-project)
                   ("c" . project-compile) ("s" . project-find-regexp)
                   ("b" . project-switch-to-buffer) ("d" . project-find-dir)
                   ("k" . project-kill-buffers)))
  (define-key dotfile-emacs-project-prefix-map (kbd (car binding)) (cdr binding)))
(global-set-key (kbd "C-c !") #'dotfile-emacs-smart-compile)
(global-set-key (kbd "C-c @") #'dotfile-emacs-smart-recompile)

;; Remaining legacy bindings -------------------------------------------------
(global-set-key (kbd "M-n") #'forward-paragraph)
(global-set-key (kbd "M-p") #'backward-paragraph)
(global-set-key (kbd "C-x p") (lambda () (interactive) (other-window -1)))
(global-set-key (kbd "C-c k") #'delete-frame)
(global-set-key (kbd "C-c K") #'save-buffers-kill-emacs)
(global-set-key (kbd "C-c s") #'eww-search-words)
(global-set-key (kbd "C-c y") #'duplicate-line)
(defun dotfile-emacs-legacy-text-scale-reset ()
  "Reset global text scaling."
  (interactive)
  (let ((last-command-event ?0)) (global-text-scale-adjust 0)))
(global-set-key (kbd "C-0") #'dotfile-emacs-legacy-text-scale-reset)
(global-set-key (kbd "C-_" ) #'undo)

(provide 'legacy-compat)
;;; legacy-compat.el ends here
