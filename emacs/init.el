;;; init.el --- Dotfile Emacs profile -*- lexical-binding: t -*-

;;; Commentary:
;; Package-enabled Emacs profile for the dotfile repo.  The machine installer
;; loads this file from ~/.emacs.d/init.el through a small stub, while tests can
;; still load it directly with a temporary HOME.  Package state is controlled by
;; DOTFILE_EMACS_STATE_DIR.

;;; Code:

(require 'cl-lib)
(require 'package)
(require 'face-remap)
(require 'subword)

(declare-function org-babel-do-load-languages "ob" (sym langs))
(declare-function global-text-scale-adjust "face-remap" (increment))
(declare-function org-element-at-point "org-element")
(declare-function org-element-property "org-element" (property element))
(declare-function org-element-type "org-element" (element))
(declare-function org-insert-todo-subheading "org")
(declare-function eat-char-mode "eat")
(declare-function eat-emacs-mode "eat")
(declare-function eat-eshell-char-mode "eat")
(declare-function eat-eshell-emacs-mode "eat")
(declare-function eat-eshell-semi-char-mode "eat")
(declare-function eat-line-mode "eat")
(declare-function eat-semi-char-mode "eat")
(declare-function eat-term-input-event "eat" (terminal n event &optional ref-pos))
(declare-function recompile "compile" (&optional edit-command))

(defvar eat-terminal)
(defvar org-edit-src-content-indentation)
(defvar org-src-fontify-natively)
(defvar org-src-preserve-indentation)
(defvar org-startup-with-inline-images)
(defvar dotfile-emacs--global-font-base-height nil)
(defvar dotfile-emacs--global-line-spacing-base nil)

(defconst dotfile-emacs-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory containing this startfile.")

(defconst dotfile-emacs-root
  (file-name-directory (directory-file-name dotfile-emacs-dir))
  "Root directory of the dotfile repo.")

(defconst dotfile-emacs-default-packages-root
  (expand-file-name "../dotfile-packages" dotfile-emacs-root)
  "Default sibling package-cache repo path.")

(add-to-list 'load-path dotfile-emacs-dir)

(defconst dotfile-emacs-package-cache
  (file-name-as-directory
   (or (getenv "DOTFILE_EMACS_PACKAGE_CACHE")
       (expand-file-name "emacs/packages"
                         (or (getenv "DOTFILE_PACKAGES")
                             dotfile-emacs-default-packages-root))))
  "Directory containing cached Emacs package tarballs.")

(defconst dotfile-emacs-state-dir
  (file-name-as-directory
   (or (getenv "DOTFILE_EMACS_STATE_DIR")
       (expand-file-name "dotfile-emacs" user-emacs-directory)))
  "Isolated state directory used by this startfile.")

(defconst dotfile-emacs-local-file
  (expand-file-name "~/.emacs.local")
  "Machine-local Emacs config loaded after the shared profile.")

(setq package-user-dir (expand-file-name "elpa" dotfile-emacs-state-dir))
(setq package-archives
      '(("gnu" . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")))
(setq package-quickstart nil)

(make-directory package-user-dir t)
(package-initialize)

(defvar dotfile-emacs-default-packages
  '(compat
    bind-key use-package
    vertico marginalia orderless embark consult embark-consult
    corfu cape popon corfu-terminal
    which-key avy
    eat
    yaml-mode dockerfile-mode markdown-mode
    diff-hl multiple-cursors rainbow-delimiters
    tempel)
  "Packages installed for the standard dotfile Emacs profile.")

(defvar dotfile-emacs-package-minimums
  '((compat . (31))
    (use-package . (2 4 6)))
  "Minimum package versions needed even when Emacs provides a built-in copy.")

(defvar dotfile-emacs-cache-preferred-packages
  '(use-package which-key)
  "Packages that should be installed into the isolated cache state.")

(defvar dotfile-emacs-offline-only
  (string= (getenv "DOTFILE_EMACS_OFFLINE") "1")
  "When non-nil, never fall back to network package installation.")

(defvar dotfile-emacs-no-install
  (string= (getenv "DOTFILE_EMACS_NO_INSTALL") "1")
  "When non-nil, configure only packages already installed in package-user-dir.")

(defun dotfile-emacs-allow-network-p ()
  "Return non-nil when network package fallback is explicitly enabled."
  (string= (getenv "DOTFILE_ALLOW_NETWORK") "1"))

(defconst dotfile-emacs-catppuccin-mocha-palette
  '((rosewater . "#f5e0dc")
    (flamingo . "#f2cdcd")
    (pink . "#f5c2e7")
    (mauve . "#cba6f7")
    (red . "#f38ba8")
    (maroon . "#eba0ac")
    (peach . "#fab387")
    (yellow . "#f9e2af")
    (green . "#a6e3a1")
    (teal . "#94e2d5")
    (sky . "#89dceb")
    (sapphire . "#74c7ec")
    (blue . "#89b4fa")
    (lavender . "#b4befe")
    (text . "#cdd6f4")
    (subtext1 . "#bac2de")
    (subtext0 . "#a6adc8")
    (overlay2 . "#9399b2")
    (overlay1 . "#7f849c")
    (overlay0 . "#6c7086")
    (surface2 . "#585b70")
    (surface1 . "#45475a")
    (surface0 . "#313244")
    (base . "#1e1e2e")
    (mantle . "#181825")
    (crust . "#11111b"))
  "Catppuccin Mocha colors matching the dotfile WezTerm theme name.")

(defconst dotfile-emacs-font-families
  '("JetBrains Mono" "Fira Code" "Cascadia Code" "Consolas")
  "Font families matching the repo WezTerm fallback order.")

(defvar dotfile-emacs--archive-refreshed nil)
(defvar dotfile-emacs--missing-packages nil)

(defvar dotfile-emacs-command-map
  (let ((map (make-sparse-keymap))) map)
  "Public dotfile command prefix map.")

(define-key global-map (kbd "C-z") dotfile-emacs-command-map)

(defun dotfile-emacs-color (name)
  "Return Catppuccin Mocha color NAME."
  (alist-get name dotfile-emacs-catppuccin-mocha-palette))

(defun dotfile-emacs-set-face (face &rest attributes)
  "Set FACE ATTRIBUTES when FACE is defined."
  (when (facep face)
    (apply #'set-face-attribute face nil attributes)))

(defun dotfile-emacs-apply-catppuccin-mocha-theme ()
  "Mimic the repo WezTerm Catppuccin Mocha color scheme."
  (setq-default cursor-type 'bar
                line-spacing 0.2)
  (blink-cursor-mode 1)
  (when (display-graphic-p)
    (set-frame-parameter nil 'alpha-background 95))

  (dotfile-emacs-set-face 'default
                           :background (dotfile-emacs-color 'base)
                           :foreground (dotfile-emacs-color 'text)
                           :weight 'bold
                           :height 130)
  (let ((font-family
         (when (display-graphic-p)
           (cl-find-if (lambda (family)
                         (find-font (font-spec :family family)))
                       dotfile-emacs-font-families))))
    (when font-family
      (dotfile-emacs-set-face 'default :family font-family)))
  (dotfile-emacs-set-face 'cursor
                           :background (dotfile-emacs-color 'rosewater))
  (dotfile-emacs-set-face 'fringe
                           :background (dotfile-emacs-color 'base)
                           :foreground (dotfile-emacs-color 'surface2))
  (dotfile-emacs-set-face 'region
                           :background (dotfile-emacs-color 'surface2)
                           :foreground (dotfile-emacs-color 'text))
  (dotfile-emacs-set-face 'highlight
                           :background (dotfile-emacs-color 'surface0)
                           :foreground (dotfile-emacs-color 'text))
  (dotfile-emacs-set-face 'hl-line
                           :background (dotfile-emacs-color 'surface0))
  (dotfile-emacs-set-face 'line-number
                           :background (dotfile-emacs-color 'base)
                           :foreground (dotfile-emacs-color 'surface1))
  (dotfile-emacs-set-face 'line-number-current-line
                           :background (dotfile-emacs-color 'surface0)
                           :foreground (dotfile-emacs-color 'lavender)
                           :weight 'bold)
  (dotfile-emacs-set-face 'minibuffer-prompt
                           :foreground (dotfile-emacs-color 'blue)
                           :weight 'bold)
  (dotfile-emacs-set-face 'vertical-border
                           :foreground (dotfile-emacs-color 'surface1))
  (dotfile-emacs-set-face 'mode-line
                           :background (dotfile-emacs-color 'surface0)
                           :foreground (dotfile-emacs-color 'text)
                           :box `(:line-width 1 :color ,(dotfile-emacs-color 'surface1)))
  (dotfile-emacs-set-face 'mode-line-inactive
                           :background (dotfile-emacs-color 'mantle)
                           :foreground (dotfile-emacs-color 'overlay0)
                           :box `(:line-width 1 :color ,(dotfile-emacs-color 'surface0)))
  (dotfile-emacs-set-face 'mode-line-buffer-id
                           :foreground (dotfile-emacs-color 'mauve)
                           :weight 'bold)
  (dotfile-emacs-set-face 'header-line
                           :background (dotfile-emacs-color 'mantle)
                           :foreground (dotfile-emacs-color 'subtext1))
  (dotfile-emacs-set-face 'link
                           :foreground (dotfile-emacs-color 'sapphire)
                           :underline t)
  (dotfile-emacs-set-face 'shadow
                           :foreground (dotfile-emacs-color 'overlay0))
  (dotfile-emacs-set-face 'success
                           :foreground (dotfile-emacs-color 'green)
                           :weight 'bold)
  (dotfile-emacs-set-face 'warning
                           :foreground (dotfile-emacs-color 'yellow)
                           :weight 'bold)
  (dotfile-emacs-set-face 'error
                           :foreground (dotfile-emacs-color 'red)
                           :weight 'bold)
  (dotfile-emacs-set-face 'isearch
                           :background (dotfile-emacs-color 'peach)
                           :foreground (dotfile-emacs-color 'base)
                           :weight 'bold)
  (dotfile-emacs-set-face 'lazy-highlight
                           :background (dotfile-emacs-color 'surface1)
                           :foreground (dotfile-emacs-color 'text))
  (dotfile-emacs-set-face 'match
                           :background (dotfile-emacs-color 'surface1)
                           :foreground (dotfile-emacs-color 'blue)
                           :weight 'bold)
  (dotfile-emacs-set-face 'show-paren-match
                           :background (dotfile-emacs-color 'teal)
                           :foreground (dotfile-emacs-color 'base)
                           :weight 'bold)
  (dotfile-emacs-set-face 'show-paren-mismatch
                           :background (dotfile-emacs-color 'red)
                           :foreground (dotfile-emacs-color 'base)
                           :weight 'bold)
  (dotfile-emacs-set-face 'whitespace-line
                           :background (dotfile-emacs-color 'base)
                           :foreground (dotfile-emacs-color 'surface1))
  (dotfile-emacs-set-face 'trailing-whitespace
                           :background (dotfile-emacs-color 'red))

  (dotfile-emacs-set-face 'font-lock-comment-face
                           :foreground (dotfile-emacs-color 'overlay0)
                           :slant 'italic)
  (dotfile-emacs-set-face 'font-lock-comment-delimiter-face
                           :foreground (dotfile-emacs-color 'overlay0))
  (dotfile-emacs-set-face 'font-lock-doc-face
                           :foreground (dotfile-emacs-color 'green)
                           :slant 'italic)
  (dotfile-emacs-set-face 'font-lock-string-face
                           :foreground (dotfile-emacs-color 'green))
  (dotfile-emacs-set-face 'font-lock-keyword-face
                           :foreground (dotfile-emacs-color 'mauve)
                           :weight 'bold)
  (dotfile-emacs-set-face 'font-lock-builtin-face
                           :foreground (dotfile-emacs-color 'red))
  (dotfile-emacs-set-face 'font-lock-function-name-face
                           :foreground (dotfile-emacs-color 'blue)
                           :weight 'bold)
  (dotfile-emacs-set-face 'font-lock-variable-name-face
                           :foreground (dotfile-emacs-color 'flamingo))
  (dotfile-emacs-set-face 'font-lock-type-face
                           :foreground (dotfile-emacs-color 'yellow))
  (dotfile-emacs-set-face 'font-lock-constant-face
                           :foreground (dotfile-emacs-color 'peach))
  (dotfile-emacs-set-face 'font-lock-warning-face
                           :foreground (dotfile-emacs-color 'red)
                           :weight 'bold)
  (dotfile-emacs-set-face 'font-lock-preprocessor-face
                           :foreground (dotfile-emacs-color 'pink))

  (dotfile-emacs-set-face 'term-color-black
                           :background (dotfile-emacs-color 'surface1)
                           :foreground (dotfile-emacs-color 'surface1))
  (dotfile-emacs-set-face 'term-color-red
                           :background (dotfile-emacs-color 'red)
                           :foreground (dotfile-emacs-color 'red))
  (dotfile-emacs-set-face 'term-color-green
                           :background (dotfile-emacs-color 'green)
                           :foreground (dotfile-emacs-color 'green))
  (dotfile-emacs-set-face 'term-color-yellow
                           :background (dotfile-emacs-color 'yellow)
                           :foreground (dotfile-emacs-color 'yellow))
  (dotfile-emacs-set-face 'term-color-blue
                           :background (dotfile-emacs-color 'blue)
                           :foreground (dotfile-emacs-color 'blue))
  (dotfile-emacs-set-face 'term-color-magenta
                           :background (dotfile-emacs-color 'pink)
                           :foreground (dotfile-emacs-color 'pink))
  (dotfile-emacs-set-face 'term-color-cyan
                           :background (dotfile-emacs-color 'teal)
                           :foreground (dotfile-emacs-color 'teal))
  (dotfile-emacs-set-face 'term-color-white
                           :background (dotfile-emacs-color 'subtext1)
                           :foreground (dotfile-emacs-color 'subtext1))
  (dotfile-emacs-set-face 'term-color-bright-black
                           :background (dotfile-emacs-color 'surface2)
                           :foreground (dotfile-emacs-color 'surface2))
  (dotfile-emacs-set-face 'term-color-bright-red
                           :background (dotfile-emacs-color 'red)
                           :foreground (dotfile-emacs-color 'red))
  (dotfile-emacs-set-face 'term-color-bright-green
                           :background (dotfile-emacs-color 'green)
                           :foreground (dotfile-emacs-color 'green))
  (dotfile-emacs-set-face 'term-color-bright-yellow
                           :background (dotfile-emacs-color 'yellow)
                           :foreground (dotfile-emacs-color 'yellow))
  (dotfile-emacs-set-face 'term-color-bright-blue
                           :background (dotfile-emacs-color 'blue)
                           :foreground (dotfile-emacs-color 'blue))
  (dotfile-emacs-set-face 'term-color-bright-magenta
                           :background (dotfile-emacs-color 'pink)
                           :foreground (dotfile-emacs-color 'pink))
  (dotfile-emacs-set-face 'term-color-bright-cyan
                           :background (dotfile-emacs-color 'teal)
                           :foreground (dotfile-emacs-color 'teal))
  (dotfile-emacs-set-face 'term-color-bright-white
                           :background (dotfile-emacs-color 'subtext0)
                           :foreground (dotfile-emacs-color 'subtext0)))

(defun dotfile-emacs-apply-catppuccin-mocha-org-faces ()
  "Apply Catppuccin Mocha colors to Org faces."
  (dotfile-emacs-set-face 'org-code
                           :background (dotfile-emacs-color 'mantle)
                           :foreground (dotfile-emacs-color 'text))
  (dotfile-emacs-set-face 'org-block
                           :background (dotfile-emacs-color 'mantle)
                           :foreground (dotfile-emacs-color 'text))
  (dotfile-emacs-set-face 'org-block-begin-line
                           :background (dotfile-emacs-color 'surface0)
                           :foreground (dotfile-emacs-color 'overlay1))
  (dotfile-emacs-set-face 'org-block-end-line
                           :background (dotfile-emacs-color 'surface0)
                           :foreground (dotfile-emacs-color 'overlay1))
  (dotfile-emacs-set-face 'org-meta-line
                           :foreground (dotfile-emacs-color 'overlay1))
  (dotfile-emacs-set-face 'org-level-1
                           :foreground (dotfile-emacs-color 'mauve)
                           :height 1.2
                           :weight 'bold)
  (dotfile-emacs-set-face 'org-level-2
                           :foreground (dotfile-emacs-color 'blue)
                           :height 1.1
                           :weight 'bold)
  (dotfile-emacs-set-face 'org-level-3
                           :foreground (dotfile-emacs-color 'green)
                           :weight 'bold)
  (dotfile-emacs-set-face 'org-level-4
                           :foreground (dotfile-emacs-color 'yellow))
  (dotfile-emacs-set-face 'org-level-5
                           :foreground (dotfile-emacs-color 'pink))
  (dotfile-emacs-set-face 'org-level-6
                           :foreground (dotfile-emacs-color 'teal))
  (dotfile-emacs-set-face 'org-level-7
                           :foreground (dotfile-emacs-color 'peach))
  (dotfile-emacs-set-face 'org-level-8
                           :foreground (dotfile-emacs-color 'red))
  (dotfile-emacs-set-face 'org-todo
                           :foreground (dotfile-emacs-color 'red)
                           :weight 'bold)
  (dotfile-emacs-set-face 'org-done
                           :foreground (dotfile-emacs-color 'green)
                           :weight 'bold)
  (dotfile-emacs-set-face 'org-date
                           :foreground (dotfile-emacs-color 'sapphire))
  (dotfile-emacs-set-face 'org-footnote
                           :foreground (dotfile-emacs-color 'pink))
  (dotfile-emacs-set-face 'org-ellipsis
                           :foreground (dotfile-emacs-color 'overlay1)
                           :weight 'bold)
  (dotfile-emacs-set-face 'org-hide
                           :foreground (dotfile-emacs-color 'base))
  (dotfile-emacs-set-face 'org-indent
                           :foreground (dotfile-emacs-color 'base)))

(defun dotfile-emacs-apply-catppuccin-mocha-completion-faces ()
  "Apply Catppuccin Mocha colors to completion package faces."
  (dotfile-emacs-set-face 'vertico-current
                           :background (dotfile-emacs-color 'surface0)
                           :foreground (dotfile-emacs-color 'text)
                           :weight 'bold)
  (dotfile-emacs-set-face 'vertico-group-title
                           :background (dotfile-emacs-color 'base)
                           :foreground (dotfile-emacs-color 'mauve)
                           :weight 'bold)
  (dotfile-emacs-set-face 'vertico-group-separator
                           :foreground (dotfile-emacs-color 'surface1)
                           :strike-through t)
  (dotfile-emacs-set-face 'completions-annotations
                           :foreground (dotfile-emacs-color 'overlay0)
                           :slant 'italic)
  (dotfile-emacs-set-face 'orderless-match-face-0
                           :foreground (dotfile-emacs-color 'blue)
                           :weight 'bold)
  (dotfile-emacs-set-face 'orderless-match-face-1
                           :foreground (dotfile-emacs-color 'mauve)
                           :weight 'bold)
  (dotfile-emacs-set-face 'orderless-match-face-2
                           :foreground (dotfile-emacs-color 'green)
                           :weight 'bold)
  (dotfile-emacs-set-face 'orderless-match-face-3
                           :foreground (dotfile-emacs-color 'peach)
                           :weight 'bold)
  (dotfile-emacs-set-face 'corfu-default
                           :background (dotfile-emacs-color 'mantle)
                           :foreground (dotfile-emacs-color 'text))
  (dotfile-emacs-set-face 'corfu-current
                           :background (dotfile-emacs-color 'surface0)
                           :foreground (dotfile-emacs-color 'text)
                           :weight 'bold)
  (dotfile-emacs-set-face 'corfu-border
                           :background (dotfile-emacs-color 'surface1))
  (dotfile-emacs-set-face 'corfu-annotations
                           :foreground (dotfile-emacs-color 'overlay0)
                           :slant 'italic)
  (dotfile-emacs-set-face 'corfu-bar
                           :background (dotfile-emacs-color 'mauve))
  (dotfile-emacs-set-face 'embark-keybinding
                           :foreground (dotfile-emacs-color 'mauve)
                           :weight 'bold))

(defun dotfile-emacs-apply-catppuccin-mocha-eat-faces ()
  "Apply Catppuccin Mocha ANSI colors to Eat faces."
  (dotfile-emacs-set-face 'eat-term-color-0
                           :background (dotfile-emacs-color 'surface1)
                           :foreground (dotfile-emacs-color 'surface1))
  (dotfile-emacs-set-face 'eat-term-color-1
                           :background (dotfile-emacs-color 'red)
                           :foreground (dotfile-emacs-color 'red))
  (dotfile-emacs-set-face 'eat-term-color-2
                           :background (dotfile-emacs-color 'green)
                           :foreground (dotfile-emacs-color 'green))
  (dotfile-emacs-set-face 'eat-term-color-3
                           :background (dotfile-emacs-color 'yellow)
                           :foreground (dotfile-emacs-color 'yellow))
  (dotfile-emacs-set-face 'eat-term-color-4
                           :background (dotfile-emacs-color 'blue)
                           :foreground (dotfile-emacs-color 'blue))
  (dotfile-emacs-set-face 'eat-term-color-5
                           :background (dotfile-emacs-color 'pink)
                           :foreground (dotfile-emacs-color 'pink))
  (dotfile-emacs-set-face 'eat-term-color-6
                           :background (dotfile-emacs-color 'teal)
                           :foreground (dotfile-emacs-color 'teal))
  (dotfile-emacs-set-face 'eat-term-color-7
                           :background (dotfile-emacs-color 'subtext1)
                           :foreground (dotfile-emacs-color 'subtext1))
  (dotfile-emacs-set-face 'eat-term-color-8
                           :background (dotfile-emacs-color 'surface2)
                           :foreground (dotfile-emacs-color 'surface2))
  (dotfile-emacs-set-face 'eat-term-color-9
                           :background (dotfile-emacs-color 'red)
                           :foreground (dotfile-emacs-color 'red))
  (dotfile-emacs-set-face 'eat-term-color-10
                           :background (dotfile-emacs-color 'green)
                           :foreground (dotfile-emacs-color 'green))
  (dotfile-emacs-set-face 'eat-term-color-11
                           :background (dotfile-emacs-color 'yellow)
                           :foreground (dotfile-emacs-color 'yellow))
  (dotfile-emacs-set-face 'eat-term-color-12
                           :background (dotfile-emacs-color 'blue)
                           :foreground (dotfile-emacs-color 'blue))
  (dotfile-emacs-set-face 'eat-term-color-13
                           :background (dotfile-emacs-color 'pink)
                           :foreground (dotfile-emacs-color 'pink))
  (dotfile-emacs-set-face 'eat-term-color-14
                           :background (dotfile-emacs-color 'teal)
                           :foreground (dotfile-emacs-color 'teal))
  (dotfile-emacs-set-face 'eat-term-color-15
                           :background (dotfile-emacs-color 'subtext0)
                           :foreground (dotfile-emacs-color 'subtext0)))

(defun dotfile-emacs-apply-catppuccin-mocha-vcs-faces ()
  "Apply Catppuccin Mocha colors to VCS gutter faces."
  (dotfile-emacs-set-face 'diff-hl-insert
                           :background (dotfile-emacs-color 'green)
                           :foreground (dotfile-emacs-color 'green))
  (dotfile-emacs-set-face 'diff-hl-change
                           :background (dotfile-emacs-color 'yellow)
                           :foreground (dotfile-emacs-color 'yellow))
  (dotfile-emacs-set-face 'diff-hl-delete
                           :background (dotfile-emacs-color 'red)
                           :foreground (dotfile-emacs-color 'red)))

(defun dotfile-emacs--cached-package-file (package)
  "Return cached tarball path for PACKAGE, or nil if absent."
  (let ((file (expand-file-name (format "%s.tar" package)
                                dotfile-emacs-package-cache)))
    (when (file-exists-p file) file)))

(defun dotfile-emacs--refresh-archives-once ()
  "Refresh package archive contents at most once."
  (unless dotfile-emacs--archive-refreshed
    (setq dotfile-emacs--archive-refreshed t)
    (package-refresh-contents)))

(defun dotfile-emacs--package-install-file (file)
  "Install package tarball FILE."
  (package-install-file file))

(defun dotfile-emacs--package-desc-satisfies-p (desc minimum)
  "Return non-nil when package DESC satisfies MINIMUM."
  (or (not minimum)
      (version-list-<= minimum (package-desc-version desc))))

(defun dotfile-emacs--package-installed-in-state-p (package minimum)
  "Return non-nil when PACKAGE is installed in `package-user-dir'."
  (cl-some
   (lambda (desc)
     (and (dotfile-emacs--package-desc-satisfies-p desc minimum)
          (file-in-directory-p (file-truename (package-desc-dir desc))
                               (file-truename package-user-dir))))
   (cdr (assq package package-alist))))

(defun dotfile-emacs--package-satisfied-p (package minimum)
  "Return non-nil when PACKAGE satisfies MINIMUM for this profile."
  (if (memq package dotfile-emacs-cache-preferred-packages)
      (dotfile-emacs--package-installed-in-state-p package minimum)
    (package-installed-p package minimum)))

(defun dotfile-emacs--install-package (package)
  "Install PACKAGE from cache first, then package archives if allowed."
  (let ((minimum (alist-get package dotfile-emacs-package-minimums)))
    (unless (dotfile-emacs--package-satisfied-p package minimum)
      (let ((cached (dotfile-emacs--cached-package-file package)))
        (cond
         (dotfile-emacs-no-install
          (push package dotfile-emacs--missing-packages))
         (cached
          (condition-case err
              (progn
                (dotfile-emacs--package-install-file cached)
                (ignore-errors (package-activate package)))
            (error
             (message "Cached install failed for %s: %s"
                      package (error-message-string err))
             (push package dotfile-emacs--missing-packages))))
         (dotfile-emacs-offline-only
          (message "Missing cached package: %s" package)
          (push package dotfile-emacs--missing-packages))
         ((not (dotfile-emacs-allow-network-p))
          (message "Missing cached package and network fallback disabled: %s" package)
          (push package dotfile-emacs--missing-packages))
         (t
          (condition-case err
              (progn
                (dotfile-emacs--refresh-archives-once)
                (package-install package))
            (error
             (message "Archive install failed for %s: %s"
                      package (error-message-string err))
             (push package dotfile-emacs--missing-packages)))))))))

(defun dotfile-emacs--ensure-packages ()
  "Install the standard package set when the Emacs version can support it."
  (if (version< emacs-version "29.1")
      (message "Skipping package layer: Emacs %s is older than 29.1"
               emacs-version)
    (dolist (package dotfile-emacs-default-packages)
      (dotfile-emacs--install-package package))))

(defmacro dotfile-emacs-use-package (name &rest args)
  "Configure NAME with use-package only when NAME is available."
  `(when (or (package-installed-p ',name) (locate-library ,(symbol-name name)))
     (use-package ,name
       :ensure nil
       ,@args)))

(defun dotfile-emacs-basic-defaults ()
  "Apply small, package-free editing defaults."
  (setq custom-file null-device)
  (setq inhibit-startup-message t
        frame-title-format '("%b - Emacs")
        initial-scratch-message ""
        use-short-answers t
        delete-by-moving-to-trash t
        save-interprogram-paste-before-kill t
        echo-keystrokes 0.8)
  (set-language-environment "UTF-8")
  (tool-bar-mode -1)
  (menu-bar-mode -1)
  (scroll-bar-mode -1)
  (global-display-line-numbers-mode 1)
  (global-auto-revert-mode 1)
  (recentf-mode 1)
  (savehist-mode 1)
  (save-place-mode 1)
  (show-paren-mode 1)
  (electric-pair-mode 1)
  (display-time-mode 1)
  (when (fboundp 'global-so-long-mode)
    (global-so-long-mode 1))
  (setq-default scroll-conservatively 101
                scroll-preserve-screen-position t
                whitespace-line-column 80
                whitespace-style '(face lines-tail))
  (add-hook 'prog-mode-hook #'whitespace-mode))

(defun dotfile-emacs--capture-typography-baseline ()
  "Capture the default face height and line-spacing before zooming."
  (unless (numberp dotfile-emacs--global-font-base-height)
    (let ((height (face-attribute 'default :height nil 'default)))
      (setq dotfile-emacs--global-font-base-height
            (if (numberp height) height 100))))
  (when (null dotfile-emacs--global-line-spacing-base)
    (setq dotfile-emacs--global-line-spacing-base
          (default-value 'line-spacing))))

(defun dotfile-emacs--sync-zoom-line-spacing ()
  "Scale numeric line-spacing in proportion to the default face height."
  (dotfile-emacs--capture-typography-baseline)
  (when (numberp dotfile-emacs--global-line-spacing-base)
    (let* ((height (face-attribute 'default :height nil 'default))
           (safe-height (if (numberp height) height
                         dotfile-emacs--global-font-base-height)))
      (setq-default line-spacing
                    (* dotfile-emacs--global-line-spacing-base
                       (/ (float safe-height)
                          dotfile-emacs--global-font-base-height))))))

(defun dotfile-emacs-text-scale-adjust (increment key)
  "Adjust global text scale by INCREMENT using KEY as the direction."
  (interactive "p")
  (dotfile-emacs--capture-typography-baseline)
  (let ((last-command-event key))
    (global-text-scale-adjust (max 1 (abs increment))))
  (dotfile-emacs--sync-zoom-line-spacing))

(defun dotfile-emacs-text-scale-increase ()
  "Increase the global text scale."
  (interactive)
  (dotfile-emacs-text-scale-adjust 1 ?=))

(defun dotfile-emacs-text-scale-decrease ()
  "Decrease the global text scale."
  (interactive)
  (dotfile-emacs-text-scale-adjust 1 ?-))

(defun dotfile-emacs-toggle-terminal ()
  "Open or switch to Eat, falling back to ANSI-term."
  (interactive)
  (cond
   ((get-buffer "*eat*") (switch-to-buffer-other-window "*eat*"))
   ((require 'eat nil t)
    (split-window-vertically)
    (other-window 1)
    (eat))
   ((get-buffer "*ansi-term*")
    (switch-to-buffer-other-window "*ansi-term*"))
   ((fboundp 'ansi-term)
    (ansi-term (or (getenv "SHELL") "/bin/sh")))
   (t (user-error "No terminal implementation available"))))

(defun dotfile-emacs-switch-to-scratch ()
  "Switch to the *scratch* buffer, creating it when needed."
  (interactive)
  (let ((created (not (get-buffer "*scratch*")))
        (buffer (get-buffer-create "*scratch*")))
    (when created
      (with-current-buffer buffer
        (lisp-interaction-mode)))
    (switch-to-buffer buffer)))

(defun dotfile-emacs-sudo-edit-current-buffer ()
  "Reopen the current file through TRAMP with root privileges."
  (interactive)
  (let ((file (buffer-file-name)))
    (if file
        (find-alternate-file (concat "/sudo::" (expand-file-name file)))
      (user-error "Current buffer is not visiting a file"))))

(defun dotfile-emacs-eat-self-input-key-sequence ()
  "Send the current key sequence to the Eat terminal."
  (interactive)
  (unless (bound-and-true-p eat-terminal)
    (user-error "Process not running"))
  (dolist (event (append (this-command-keys-vector) nil))
    (eat-term-input-event eat-terminal 1 event)))

(defvar dotfile-emacs-eat-c-x-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "B") #'dotfile-emacs-switch-to-scratch)
    (define-key map [t] #'dotfile-emacs-eat-self-input-key-sequence)
    map)
  "Eat char-mode `C-x' prefix map with a scratch escape hatch.")

(defun dotfile-emacs-bind-eat-keys ()
  "Bind dotfile keys in Eat terminal keymaps."
  (when (boundp 'eat-mode-map)
    (define-key eat-mode-map (kbd "C-c C-e") #'eat-emacs-mode)
    (define-key eat-mode-map (kbd "C-c C-s") #'eat-semi-char-mode)
    (define-key eat-mode-map (kbd "C-c C-d") #'eat-char-mode)
    (define-key eat-mode-map (kbd "C-x B")
                #'dotfile-emacs-switch-to-scratch))
  (when (boundp 'eat-semi-char-mode-map)
    (define-key eat-semi-char-mode-map (kbd "C-c C-e") #'eat-emacs-mode)
    (define-key eat-semi-char-mode-map (kbd "C-c C-s") #'eat-semi-char-mode)
    (define-key eat-semi-char-mode-map (kbd "C-c C-d") #'eat-char-mode))
  (when (boundp 'eat-line-mode-map)
    (define-key eat-line-mode-map (kbd "C-c C-e") #'eat-emacs-mode)
    (define-key eat-line-mode-map (kbd "C-c C-s") #'eat-semi-char-mode)
    (define-key eat-line-mode-map (kbd "C-c C-d") #'eat-char-mode))
  (when (boundp 'eat-char-mode-map)
    (define-key eat-char-mode-map (kbd "C-x")
                dotfile-emacs-eat-c-x-map))
  (when (boundp 'eat-eshell-emacs-mode-map)
    (define-key eat-eshell-emacs-mode-map (kbd "C-c C-e")
                #'eat-eshell-emacs-mode)
    (define-key eat-eshell-emacs-mode-map (kbd "C-c C-s")
                #'eat-eshell-semi-char-mode)
    (define-key eat-eshell-emacs-mode-map (kbd "C-c C-d")
                #'eat-eshell-char-mode))
  (when (boundp 'eat-eshell-semi-char-mode-map)
    (define-key eat-eshell-semi-char-mode-map (kbd "C-c C-e")
                #'eat-eshell-emacs-mode)
    (define-key eat-eshell-semi-char-mode-map (kbd "C-c C-s")
                #'eat-eshell-semi-char-mode)
    (define-key eat-eshell-semi-char-mode-map (kbd "C-c C-d")
                #'eat-eshell-char-mode))
  (when (boundp 'eat-eshell-char-mode-map)
    (define-key eat-eshell-char-mode-map (kbd "C-x")
                dotfile-emacs-eat-c-x-map)))

(defun dotfile-emacs-indent-buffer ()
  "Indent the whole buffer."
  (interactive)
  (indent-region (point-min) (point-max)))

(defun dotfile-emacs--insert-template (template)
  "Insert TEMPLATE and move point to its %? marker when present."
  (let ((start (point))
        target)
    (insert template)
    (save-excursion
      (goto-char start)
      (when (search-forward "%?" nil t)
        (replace-match "" nil t)
        (setq target (copy-marker (point) t))))
    (indent-region start (point))
    (when target
      (goto-char target))))

(defun dotfile-emacs-org-insert ()
  "Insert a public-safe Org template."
  (interactive)
  (let ((choice (completing-read
                 "Org insert: "
                 '("src" "shell" "emacs-lisp" "lisp" "python" "js" "json" "conf"
                   "table" "example" "quote" "verse" "center" "comment"
                   "image" "footnote" "todo-sub")
                 nil t)))
    (pcase choice
      ("todo-sub" (org-insert-todo-subheading))
      ("table" (dotfile-emacs--insert-template
                 "| Function | Key |\n|----------+-----|\n| %? | |\n"))
      ("src" (dotfile-emacs--insert-template
               "#+begin_src %?\n\n#+end_src\n"))
      ((or "shell" "emacs-lisp" "lisp" "python" "js" "json" "conf")
       (dotfile-emacs--insert-template
        (format "#+begin_src %s\n%%?\n#+end_src\n"
                (if (string= choice "conf") "conf" choice))))
      ((or "example" "quote" "verse" "center" "comment")
       (dotfile-emacs--insert-template
        (format "#+begin_%s\n%%?\n#+end_%s\n" choice choice)))
      ("image" (dotfile-emacs--insert-template
                 "#+caption: %?\n#+name: fig:\n[[./image.png]]\n"))
      ("footnote" (dotfile-emacs--insert-template "[fn:1] %?\n")))))

(defun dotfile-emacs-org-copy-block-content ()
  "Copy the content of the Org block at point."
  (interactive)
  (require 'org-element)
  (let* ((element (org-element-at-point))
         (type (org-element-type element))
         content)
    (if (memq type '(src-block example-block comment-block export-block
                               fixed-width))
        (setq content (org-element-property :value element))
      (let ((beg (org-element-property :contents-begin element))
            (end (org-element-property :contents-end element)))
        (when (and beg end)
          (setq content (buffer-substring-no-properties beg end)))))
    (if content
        (progn
          (kill-new content)
          (message "Copied content from %s" type))
      (user-error "Not inside a supported Org block"))))

(defun dotfile-emacs-org-mode-setup ()
  "Apply public-safe Org buffer bindings."
  (local-set-key (kbd "C-c i") #'dotfile-emacs-org-insert)
  (local-set-key (kbd "C-c w") #'dotfile-emacs-org-copy-block-content))

(with-eval-after-load 'org
  (setq org-src-fontify-natively t)
  (setq org-startup-with-inline-images t)
  (setq org-edit-src-content-indentation 0)
  (setq org-src-preserve-indentation nil)
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (lisp . t)
     (shell . t)))
  (dotfile-emacs-apply-catppuccin-mocha-org-faces)
  (add-hook 'org-mode-hook #'dotfile-emacs-org-mode-setup))

(dotfile-emacs-basic-defaults)
(dotfile-emacs-apply-catppuccin-mocha-theme)
(dotfile-emacs--ensure-packages)

(setq dotfile-emacs-prompt-file (expand-file-name "prompts.org" dotfile-emacs-dir))
(require 'dotfile-emacs-prompt nil t)

(when (featurep 'dotfile-emacs-prompt)
  (define-key dotfile-emacs-command-map (kbd ";") #'dotfile-emacs-prompt-copy)
  (define-key dotfile-emacs-command-map (kbd ":")
              #'dotfile-emacs-prompt-bridge-primary-to-pasteboard))

(when (require 'use-package nil t)
  (setq use-package-always-ensure nil)

  (dotfile-emacs-use-package which-key
    :custom
    (which-key-idle-delay 0.4)
    (which-key-idle-secondary-delay 0.05)
    :init
    (which-key-mode 1)
    :config
    (when (fboundp 'which-key-add-key-based-replacements)
      (which-key-add-key-based-replacements
        "C-z" "dotfile"
        "C-z ;" "prompt copy"
        "C-z :" "primary to clipboard"
        "C-c p" "project")))

  (dotfile-emacs-use-package vertico
    :init
    (vertico-mode 1)
    :config
    (dotfile-emacs-apply-catppuccin-mocha-completion-faces))

  (dotfile-emacs-use-package marginalia
    :after vertico
    :init
    (marginalia-mode 1))

  (dotfile-emacs-use-package orderless
    :custom
    (completion-styles '(orderless basic))
    (completion-category-defaults nil)
    (completion-category-overrides '((file (styles partial-completion))))
    :config
    (dotfile-emacs-apply-catppuccin-mocha-completion-faces))

  (dotfile-emacs-use-package consult
    :bind (("C-x b" . consult-buffer)
           ("M-g g" . consult-goto-line)
           ("M-s r" . consult-ripgrep)
           ("M-s l" . consult-line)))

  (dotfile-emacs-use-package corfu
    :custom
    (corfu-auto t)
    (corfu-auto-delay 0.05)
    (corfu-auto-prefix 1)
    (corfu-cycle t)
    (corfu-preselect 'prompt)
    :init
    (global-corfu-mode 1)
    (corfu-history-mode 1)
    (corfu-popupinfo-mode 1)
    :config
    (dotfile-emacs-apply-catppuccin-mocha-completion-faces))

  (dotfile-emacs-use-package corfu-terminal
    :if (not (display-graphic-p))
    :after corfu
    :init
    (corfu-terminal-mode 1))

  (dotfile-emacs-use-package cape
    :init
    (add-to-list 'completion-at-point-functions #'cape-abbrev)
    (add-to-list 'completion-at-point-functions #'cape-dabbrev)
    (add-to-list 'completion-at-point-functions #'cape-file)
    :config
    (setq cape-dabbrev-min-length 2))

  (dotfile-emacs-use-package embark
    :bind (("C-." . embark-act)
           ("C-;" . embark-dwim)
           ("C-h B" . embark-bindings))
    :init
    (setq prefix-help-command #'embark-prefix-help-command)
    :config
    (dotfile-emacs-apply-catppuccin-mocha-completion-faces))

  (dotfile-emacs-use-package embark-consult
    :after (embark consult))

  (dotfile-emacs-use-package tempel
    :bind (("M-+" . tempel-complete)
           ("M-*" . tempel-insert)))

  (dotfile-emacs-use-package avy
    :bind (("C-:" . avy-goto-char-timer)
           ("M-g f" . avy-goto-line)
           ("M-g w" . avy-goto-word-1)
           ("C-c j" . avy-goto-char-timer)))

  (dotfile-emacs-use-package eat
    :commands eat
    :bind (("C-c t" . dotfile-emacs-toggle-terminal))
    :config
    (dotfile-emacs-bind-eat-keys)
    (dotfile-emacs-apply-catppuccin-mocha-eat-faces))

  (dotfile-emacs-use-package yaml-mode
    :mode ("\\.ya?ml\\'" . yaml-mode))

  (dotfile-emacs-use-package dockerfile-mode
    :mode ("Dockerfile\\'" . dockerfile-mode)
    :config
    (setq dockerfile-mode-command "docker"))

  (dotfile-emacs-use-package markdown-mode
    :mode (("README\\.md\\'" . gfm-mode)
           ("\\.md\\'" . markdown-mode)))

  (dotfile-emacs-use-package diff-hl
    :init
    (global-diff-hl-mode 1)
    :config
    (dotfile-emacs-apply-catppuccin-mocha-vcs-faces)
    :hook ((dired-mode . diff-hl-dired-mode)
           (magit-post-refresh . diff-hl-magit-post-refresh)))

  (dotfile-emacs-use-package multiple-cursors
    :bind (("M--" . mc/mark-previous-like-this)
           ("M-=" . mc/mark-next-like-this)
           ("M-_" . mc/skip-to-previous-like-this)
           ("M-+" . mc/skip-to-next-like-this)))

  (dotfile-emacs-use-package rainbow-delimiters
    :hook (prog-mode . rainbow-delimiters-mode)))

(global-set-key (kbd "C-x SPC") #'set-mark-command)
(global-set-key (kbd "C-x >") #'end-of-buffer)
(global-set-key (kbd "C-x <") #'beginning-of-buffer)
(global-set-key (kbd "C-c c") #'replace-string)
(global-set-key (kbd "C-c q") #'read-only-mode)
(global-set-key (kbd "M-F") #'subword-right)
(global-set-key (kbd "M-B") #'subword-left)
(global-set-key (kbd "C-c Q") #'dotfile-emacs-sudo-edit-current-buffer)
(global-set-key (kbd "C-c TAB") #'dotfile-emacs-indent-buffer)
(global-set-key (kbd "C-x B") #'dotfile-emacs-switch-to-scratch)
(global-set-key (kbd "C--") #'dotfile-emacs-text-scale-decrease)
(global-set-key (kbd "C-=") #'dotfile-emacs-text-scale-increase)
(global-set-key (kbd "C-+") #'dotfile-emacs-text-scale-increase)

;; Public compatibility features retained from the legacy profile.  This is
;; loaded last so intentional public key choices (notably C-c p) are final,
;; while private vault configuration can still override them in .emacs.local.
(require 'legacy-compat)

(load dotfile-emacs-local-file t t)

(when dotfile-emacs--missing-packages
  (message "Missing dotfile Emacs packages: %s"
           (mapconcat #'symbol-name
                      (delete-dups (nreverse dotfile-emacs--missing-packages))
                      ", ")))

(provide 'dotfile-emacs-init)
;;; init.el ends here
