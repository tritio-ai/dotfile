;;; early-init.el --- Dotfile Emacs early init -*- lexical-binding: t -*-

;;; Commentary:
;; Early UI/package startup settings for the dotfile Emacs profile.

;;; Code:

(defconst dotfile-emacs-gc-normal-threshold (* 16 1024 1024)
  "Garbage collection threshold restored after startup.")
(defvar dotfile-emacs--startup-file-name-handler-alist file-name-handler-alist)

(setq gc-cons-threshold most-positive-fixnum
      file-name-handler-alist nil
      read-process-output-max (* 1024 1024))

(defun dotfile-emacs-restore-startup-performance ()
  "Restore normal garbage collection and file handlers after startup."
  (setq gc-cons-threshold dotfile-emacs-gc-normal-threshold
        file-name-handler-alist
        (append dotfile-emacs--startup-file-name-handler-alist
                file-name-handler-alist)))

(if after-init-time
    (dotfile-emacs-restore-startup-performance)
  (add-hook 'emacs-startup-hook #'dotfile-emacs-restore-startup-performance))

(setq package-enable-at-startup nil)
(setq frame-inhibit-implied-resize t)
(setq frame-resize-pixelwise t)

(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)
(push '(background-color . "#1e1e2e") default-frame-alist)
(push '(foreground-color . "#cdd6f4") default-frame-alist)
(push '(cursor-color . "#f5e0dc") default-frame-alist)
(push '(alpha-background . 95) default-frame-alist)

;;; early-init.el ends here
