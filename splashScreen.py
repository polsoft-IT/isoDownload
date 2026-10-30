#!/usr/bin/env python3
"""
splashScreen - polsoft.ITS(TM) Developers Splash Screen & Tools Hub
Python version with identical appearance and functionality to original PowerShell script.
"""

import sys
import os
import subprocess
import argparse
import shutil
from pathlib import Path
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
                             QLabel, QPushButton, QProgressBar, QGridLayout, QFrame,
                             QScrollArea, QMessageBox, QDesktopWidget, QSizePolicy,
                             QDialog, QGraphicsDropShadowEffect, QShortcut)
from PyQt5.QtGui import QKeySequence
from PyQt5.QtCore import Qt, QTimer, QPropertyAnimation, QEasingCurve, QPoint, QSize
from PyQt5.QtGui import QFont, QColor, QPixmap, QCursor, QDesktopServices, QPainter, QPen
from PyQt5.QtCore import QUrl


# Jedno źródło praw dla motywu (ciemny theme w całej aplikacji)
PALETTE = {
    "bg":     "#0d1117",
    "panel":  "#161b22",
    "card":   "#1c2128",
    "border": "#30363d",
    "text":   "#e6edf3",
    "muted":  "#8b949e",
    "accent": "#00d4ff",
    "ok":     "#2ecc71",
    "warn":   "#ff8c42",
    "err":    "#e74c3c",
}


class ShadowBorder(QFrame):
    """Frame with drop shadow effect"""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.shadow_color = QColor("#00d4ff")  # Modern cyan blue
        self.shadow_blur = 32  # Increased blur for softer effect
        self.shadow_opacity = 0.6  # Slightly more visible

    def paintEvent(self, event):
        super().paintEvent(event)
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        # Draw shadow
        shadow_color = QColor(self.shadow_color)
        shadow_color.setAlphaF(self.shadow_opacity)
        pen = QPen(shadow_color, self.shadow_blur)
        pen.setCapStyle(Qt.RoundCap)
        painter.setPen(pen)
        painter.setBrush(Qt.NoBrush)

        # Draw rounded rectangle with shadow
        rect = self.rect().adjusted(
            self.shadow_blur // 2,
            self.shadow_blur // 2,
            -self.shadow_blur // 2,
            -self.shadow_blur // 2
        )
        painter.drawRoundedRect(rect, 16, 16)


class SplashScreen(QMainWindow):
    def __init__(self, duration_sec=3, splash_only=False, skip_splash=False, image_path=None):
        super().__init__()

        # Parameters
        self.duration_sec = duration_sec
        self.splash_only = splash_only
        self.skip_splash = skip_splash
        self.image_path = image_path

        # App info
        self.app_title = "polsoft.ITS(TM) Developers - Tools Hub"
        self.app_author = "Sebastian Januchowski @ polsoft.ITS(TM) Dev"
        self.app_email = "polsoft.its@mail.com"
        self.app_github = "https://github.com/polsoft-it"

        # Script directory
        self.script_dir = Path(__file__).parent

        # State
        self.in_dashboard = False
        self.splash_timer = None
        self.timer_total_steps = 100
        self.timer_current_step = 0

        # Tools catalog with enhanced modern colors
        self.tools_catalog = [
            {"file": "scripts/isoMicrosoft.ps1", "name": "isoMicrosoft", "badge": "ALL-IN-ONE",
             "color": "#d4a5ff", "desc": "Universal Windows & Office downloader with adaptive questionnaire."},
            {"file": "scripts/isoWindows.ps1", "name": "isoWindows", "badge": "WINDOWS",
             "color": "#5dade2", "desc": "Official Microsoft Windows 11, 10, 8.1 ISO & ESD connector."},
            {"file": "scripts/isoOffice.ps1", "name": "isoOffice", "badge": "OFFICE",
             "color": "#ff8c42", "desc": "Microsoft Office 2024, 2021, 2019, 2016 Retail & Volume packages."},
            {"file": "scripts/isoLinux.ps1", "name": "isoLinux", "badge": "LINUX / VM",
             "color": "#2ecc71", "desc": "Ubuntu, Debian, Fedora, Mint, Kali, Arch & Proxmox VE."},
            {"file": "scripts/isoRescue.ps1", "name": "isoRescue", "badge": "RESCUE",
             "color": "#e74c3c", "desc": "Hiren's BootCD PE, SystemRescue, Rescuezilla, Clonezilla & GParted."},
            {"file": "scripts/isoServer.ps1", "name": "isoServer", "badge": "SERVER",
             "color": "#00d4ff", "desc": "Windows Server 2025, 2022, 2019, 2016 & Azure Edition."},
            {"file": "scripts/odtConfig.ps1", "name": "odtConfig", "badge": "ODT TOOL",
             "color": "#f1c40f", "desc": "Visual Office Deployment Tool XML generator & unattended installer."},
            {"file": "scripts/isoVerify.ps1", "name": "isoVerify", "badge": "INTEGRITY",
             "color": "#1abc9c", "desc": "SHA256, SHA1, MD5, Authenticode signature & MSDN database checker."},
            {"file": "scripts/isoVentoy.ps1", "name": "isoVentoy", "badge": "BOOT USB",
             "color": "#9b59b6", "desc": "Ventoy multi-boot USB installer, Win11 bypasses & ISO manager."},
        ]

        # Drag position
        self.drag_pos = None

        # Setup UI
        self.setup_ui()
        self.load_splash_image()
        self.setup_connections()

        # Show window
        self.show_centered()

        # Start splash animation
        if not self.skip_splash:
            self.start_splash_timer()
        else:
            self.transition_to_dashboard()

    def setup_ui(self):
        """Setup the main window and UI (identical to XAML)"""
        self.setWindowTitle("polsoft.ITS Developers Tools Hub")
        self.setFixedSize(980, 760)
        self.setWindowFlags(Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
        self.setAttribute(Qt.WA_TranslucentBackground)

        # Main widget with transparent background
        self.main_widget = QWidget()
        self.main_widget.setAttribute(Qt.WA_TranslucentBackground)
        self.setCentralWidget(self.main_widget)

        # Main layout
        main_layout = QVBoxLayout(self.main_widget)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)

        # Outer Border with Glow - updated size to accommodate all visual enhancements
        self.outer_border = ShadowBorder()
        self.outer_border.setStyleSheet(f"""
            ShadowBorder {{
                background-color: {PALETTE['bg']};
                border: 2px solid {PALETTE['border']};
                border-radius: 16px;
            }}
        """)
        self.outer_border.setFixedSize(950, 730)

        main_layout.addWidget(self.outer_border, 0, Qt.AlignCenter)

        # Content layout inside border
        content_layout = QVBoxLayout(self.outer_border)
        content_layout.setContentsMargins(0, 0, 0, 0)
        content_layout.setSpacing(0)

        # Create views
        self.create_splash_view()
        self.create_dashboard_view()

        # Initially show splash
        self.view_splash.show()
        self.view_dashboard.hide()

    def create_splash_view(self):
        """Create the splash screen view (updated to fit new window size)"""
        self.view_splash = QWidget()
        self.view_splash.setFixedSize(920, 700)
        self.view_splash.setCursor(QCursor(Qt.PointingHandCursor))

        # Layout
        splash_layout = QVBoxLayout(self.view_splash)
        splash_layout.setContentsMargins(0, 0, 0, 0)
        splash_layout.setSpacing(0)

        # Splash image/background
        self.splash_image = QLabel()
        self.splash_image.setAlignment(Qt.AlignCenter)
        self.splash_image.setStyleSheet("background-color: transparent;")
        self.splash_image.setFixedSize(920, 700)

        # Fallback vector design (enhanced modern gradient)
        self.vector_fallback = QFrame()
        self.vector_fallback.setFixedSize(920, 700)
        self.vector_fallback.setStyleSheet("""
            QFrame {
                background: qradialgradient(
                    cx:0.5, cy:0.5, radius:0.8,
                    fx:0.5, fy:0.5,
                    stop:0 #1a1f2e,
                    stop:1 #0d1117
                );
            }
        """)
        self.vector_fallback.hide()

        vector_layout = QVBoxLayout(self.vector_fallback)
        vector_layout.setContentsMargins(0, 0, 0, 0)
        vector_layout.setSpacing(0)

        # Vector content box (enhanced modern colors)
        vector_box = QFrame()
        vector_box.setStyleSheet("""
            QFrame {
                background-color: rgba(13, 17, 23, 0.85);
                border: 2px solid #d4a5ff;
                border-radius: 12px;
            }
        """)
        vector_box.setFixedSize(640, 300)

        vector_box_layout = QVBoxLayout(vector_box)
        vector_box_layout.setContentsMargins(25, 25, 25, 25)
        vector_box_layout.setSpacing(8)

        # Title: polsoft.ITS(TM) Developers (enhanced modern colors)
        title = QLabel("polsoft.ITS(TM) Developers")
        title.setStyleSheet("color: #ffffff; font-size: 32px; font-weight: bold; background: transparent;")
        title.setAlignment(Qt.AlignCenter)

        # Author: Sebastian Januchowski (enhanced modern colors)
        author = QLabel("Sebastian Januchowski")
        author.setStyleSheet("color: #2ecc71; font-size: 20px; font-weight: bold; background: transparent;")
        author.setAlignment(Qt.AlignCenter)

        # Separator (enhanced modern color)
        separator = QFrame()
        separator.setFrameShape(QFrame.HLine)
        separator.setStyleSheet("""
            QFrame {
                background-color: #30363d;
                max-width: 560px;
            }
        """)
        separator.setFixedHeight(1)

        # Email: polsoft.its@mail.com (enhanced modern color)
        email = QLabel(self.app_email)
        email.setStyleSheet("color: #00d4ff; font-size: 15px; background: transparent;")
        email.setAlignment(Qt.AlignCenter)

        # GitHub: https://github.com/polsoft-it (enhanced modern color)
        github = QLabel(self.app_github)
        github.setStyleSheet("color: #ff8c42; font-size: 15px; background: transparent;")
        github.setAlignment(Qt.AlignCenter)

        vector_box_layout.addWidget(title)
        vector_box_layout.addWidget(author)
        vector_box_layout.addSpacing(24)
        vector_box_layout.addWidget(separator)
        vector_box_layout.addSpacing(20)
        vector_box_layout.addWidget(email)
        vector_box_layout.addSpacing(6)
        vector_box_layout.addWidget(github)

        vector_layout.addWidget(vector_box, 0, Qt.AlignCenter)

        # Overlay Controls (VerticalAlignment Bottom, Margin 20,0,20,15)
        overlay_widget = QWidget()
        overlay_widget.setFixedHeight(50)
        overlay_layout = QHBoxLayout(overlay_widget)
        overlay_layout.setContentsMargins(20, 0, 20, 15)
        overlay_layout.setSpacing(0)

        self.splash_hint = QLabel("Click anywhere or wait to enter Tools Hub...")
        self.splash_hint.setStyleSheet("color: #e6edf3; font-size: 11px; background: transparent;")
        self.splash_hint.setAlignment(Qt.AlignVCenter)

        self.btn_open_hub = QPushButton("Enter Tools Hub >>")
        self.btn_open_hub.setStyleSheet("""
            QPushButton {
                background-color: #00d4ff;
                color: #0d1117;
                font-weight: bold;
                padding: 6px 14px;
                border-radius: 6px;
                border: none;
            }
            QPushButton:hover {
                background-color: #00b8e6;
            }
        """)
        self.btn_open_hub.setFixedSize(150, 32)

        overlay_layout.addWidget(self.splash_hint)
        overlay_layout.addStretch()
        overlay_layout.addWidget(self.btn_open_hub)

        # Progress Bar (enhanced modern color)
        self.progress_bar = QProgressBar()
        self.progress_bar.setFixedHeight(3)
        self.progress_bar.setTextVisible(False)
        self.progress_bar.setStyleSheet("""
            QProgressBar {
                background-color: transparent;
                border: none;
            }
            QProgressBar::chunk {
                background-color: #00d4ff;
            }
        """)
        self.progress_bar.setValue(100)
        self.progress_bar.setRange(0, 100)

        # Stack images and fallback
        image_stack = QWidget()
        image_stack.setFixedSize(920, 650)
        image_stack_layout = QVBoxLayout(image_stack)
        image_stack_layout.setContentsMargins(0, 0, 0, 0)
        image_stack_layout.addWidget(self.splash_image)
        image_stack_layout.addWidget(self.vector_fallback)

        # Add to splash layout
        splash_layout.addWidget(image_stack)
        splash_layout.addWidget(overlay_widget)
        splash_layout.addWidget(self.progress_bar)

        content_layout = QVBoxLayout(self.outer_border)
        content_layout.addWidget(self.view_splash)

    def create_dashboard_view(self):
        """Create the dashboard/tools hub view (updated to fit new window size)"""
        self.view_dashboard = QWidget()
        self.view_dashboard.setFixedSize(920, 700)
        self.view_dashboard.hide()

        dashboard_layout = QVBoxLayout(self.view_dashboard)
        dashboard_layout.setContentsMargins(20, 20, 20, 20)
        dashboard_layout.setSpacing(10)

        # Header Bar (Margin 0,0,0,10, Padding 0,0,0,10, BorderBrush #313244, BorderThickness 0,0,0,1)
        self.create_dashboard_header(dashboard_layout)

        # System Pre-flight & Environment Ribbon (Background #11111b, CornerRadius 8, Padding 10,6, Margin 0,0,0,10)
        self.create_status_ribbon(dashboard_layout)

        # Tools Grid (3x3 Cards, Margin 0,0,0,10)
        self.create_tools_grid(dashboard_layout)

        # Footer Bar (Margin 0,6,0,0)
        self.create_dashboard_footer(dashboard_layout)

        content_layout = QVBoxLayout(self.outer_border)
        content_layout.addWidget(self.view_dashboard)

    def create_dashboard_header(self, layout):
        """Create the dashboard header"""
        header_frame = QFrame()
        header_frame.setStyleSheet(f"""
            QFrame {{
                border: none;
                border-bottom: 1px solid {PALETTE['border']};
                background: transparent;
            }}
        """)
        header_layout = QVBoxLayout(header_frame)
        header_layout.setContentsMargins(0, 0, 0, 10)
        header_layout.setSpacing(3)

        # Title & Branding - Professional hierarchy
        title_row = QHBoxLayout()
        title_row.setSpacing(12)

        # Main brand with subtle glow effect
        title1 = QLabel("polsoft.ITS<span style='color:#666; font-size:16px;'>(TM)</span>")
        title1.setTextFormat(Qt.RichText)
        title1.setStyleSheet(f"color: {PALETTE['accent']}; font-size: 26px; font-weight: 900; background: transparent; letter-spacing: 1px;")
        
        title2 = QLabel("Developers Tools Hub")
        title2.setStyleSheet(f"color: {PALETTE['muted']}; font-size: 18px; font-weight: 500; background: transparent; margin-top: 4px;")

        title_row.addWidget(title1)
        title_row.addWidget(title2)
        title_row.addStretch()

        # Subtitle row
        subtitle_row = QHBoxLayout()
        subtitle_row.setSpacing(16)

        author = QLabel("By Sebastian Januchowski")
        author.setStyleSheet(f"color: {PALETTE['muted']}; font-size: 12px; background: transparent;")

        # GitHub Badge Button with icon
        self.github_btn = QPushButton("⌘ GitHub")
        self.github_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: {PALETTE['panel']};
                color: {PALETTE['accent']};
                font-size: 11px;
                font-weight: bold;
                padding: 4px 10px;
                border-radius: 6px;
                border: 1px solid {PALETTE['border']};
            }}
            QPushButton:hover {{
                background-color: #21262d;
                border-color: {PALETTE['accent']};
            }}
        """)
        self.github_btn.setCursor(QCursor(Qt.PointingHandCursor))
        self.github_btn.setFixedHeight(28)

        # Email Badge Button with icon
        self.email_btn = QPushButton("✉ Email")
        self.email_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: {PALETTE['panel']};
                color: {PALETTE['accent']};
                font-size: 11px;
                font-weight: bold;
                padding: 4px 10px;
                border-radius: 6px;
                border: 1px solid {PALETTE['border']};
            }}
            QPushButton:hover {{
                background-color: #21262d;
                border-color: {PALETTE['accent']};
            }}
        """)
        self.email_btn.setCursor(QCursor(Qt.PointingHandCursor))
        self.email_btn.setFixedHeight(28)

        subtitle_row.addWidget(author)
        subtitle_row.addWidget(self.github_btn)
        subtitle_row.addWidget(self.email_btn)
        subtitle_row.addStretch()

        # Buttons row - Professional window controls (light mode)
        buttons_row = QHBoxLayout()
        buttons_row.setSpacing(8)

        self.btn_refresh = QPushButton("⟳ Refresh")
        self.btn_refresh.setFixedSize(90, 32)
        self.btn_refresh.setStyleSheet(f"""
            QPushButton {{
                background-color: {PALETTE['panel']};
                color: {PALETTE['text']};
                font-size: 12px;
                font-weight: bold;
                border-radius: 6px;
                border: 1px solid {PALETTE['border']};
                padding: 6px 10px;
            }}
            QPushButton:hover {{
                background-color: #21262d;
                border-color: {PALETTE['accent']};
            }}
        """)
        self.btn_refresh.setCursor(QCursor(Qt.PointingHandCursor))

        self.btn_close = QPushButton("✕")
        self.btn_close.setFixedSize(36, 32)
        self.btn_close.setStyleSheet(f"""
            QPushButton {{
                background-color: {PALETTE['panel']};
                color: {PALETTE['err']};
                font-weight: bold;
                font-size: 14px;
                border-radius: 6px;
                border: 1px solid {PALETTE['border']};
            }}
            QPushButton:hover {{
                background-color: #21262d;
                border-color: {PALETTE['err']};
            }}
        """)
        self.btn_close.setCursor(QCursor(Qt.PointingHandCursor))

        # About button (info icon only)
        self.btn_about = QPushButton("?")
        self.btn_about.setFixedSize(36, 32)
        self.btn_about.setStyleSheet("""
            QPushButton {
                background-color: #21262d;
                color: #00d4ff;
                font-size: 14px;
                font-weight: bold;
                border-radius: 6px;
                border: none;
            }
            QPushButton:hover {
                background-color: #30363d;
            }
        """)
        self.btn_about.setToolTip("O programie")

        buttons_row.addStretch()
        buttons_row.addWidget(self.btn_about)
        buttons_row.addWidget(self.btn_refresh)
        buttons_row.addWidget(self.btn_close)

        header_layout.addLayout(title_row)
        header_layout.addLayout(subtitle_row)
        header_layout.addLayout(buttons_row)

        layout.addWidget(header_frame)

    def create_status_ribbon(self, layout):
        """Create the system status ribbon (identical to XAML)"""
        ribbon = QFrame()
        ribbon.setStyleSheet(f"""
            QFrame {{
                background-color: {PALETTE['panel']};
                border: 1px solid {PALETTE['border']};
                border-radius: 8px;
            }}
        """)
        ribbon_layout = QHBoxLayout(ribbon)
        ribbon_layout.setContentsMargins(10, 6, 10, 6)
        ribbon_layout.setSpacing(8)

        # Admin Badge (enhanced modern colors)
        self.admin_badge = QLabel("CHECKING RIGHTS")
        self.admin_badge.setStyleSheet("""
            QLabel {
                background-color: #21262d;
                color: #8b949e;
                font-size: 10px;
                font-weight: bold;
                padding: 3px 8px;
                border-radius: 4px;
            }
        """)

        # Elevate Button (enhanced modern colors)
        self.btn_elevate = QPushButton("Restart as Admin")
        self.btn_elevate.setStyleSheet("""
            QPushButton {
                background-color: #f1c40f;
                color: #0d1117;
                font-size: 10px;
                font-weight: bold;
                padding: 1px 8px;
                border-radius: 4px;
                border: none;
                height: 22px;
            }
        """)
        self.btn_elevate.hide()

        # Network Badge (enhanced modern colors)
        self.net_status = QLabel("CHECKING NET")
        self.net_status.setStyleSheet("""
            QLabel {
                background-color: #21262d;
                color: #8b949e;
                font-size: 10px;
                font-weight: bold;
                padding: 3px 8px;
                border-radius: 4px;
            }
        """)

        # PS Version Badge (enhanced modern colors)
        self.ps_version = QLabel("PowerShell")
        self.ps_version.setStyleSheet("""
            QLabel {
                background-color: #21262d;
                color: #00d4ff;
                font-size: 10px;
                padding: 3px 8px;
                border-radius: 4px;
            }
        """)

        # Disk Space Badge (enhanced modern colors)
        self.disk_space = QLabel("Disk")
        self.disk_space.setStyleSheet("""
            QLabel {
                background-color: #21262d;
                color: #ff8c42;
                font-size: 10px;
                padding: 3px 8px;
                border-radius: 4px;
            }
        """)

        # Status Indicator (enhanced modern color)
        self.status_ok = QLabel("SYSTEM STATUS OK")
        self.status_ok.setStyleSheet("""
            QLabel {
                color: #2ecc71;
                font-size: 10px;
                font-weight: bold;
                background: transparent;
            }
        """)

        ribbon_layout.addWidget(self.admin_badge)
        ribbon_layout.addWidget(self.btn_elevate)
        ribbon_layout.addWidget(self.net_status)
        ribbon_layout.addWidget(self.ps_version)
        ribbon_layout.addWidget(self.disk_space)
        ribbon_layout.addStretch()
        ribbon_layout.addWidget(self.status_ok)

        layout.addWidget(ribbon)

    def create_tools_grid(self, layout):
        """Create the tools grid inside a scroll area"""
        self.tools_widget = QWidget()
        self.tools_layout = QGridLayout(self.tools_widget)
        self.tools_layout.setSpacing(16)
        self.tools_layout.setContentsMargins(25, 25, 25, 25)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setWidget(self.tools_widget)
        scroll.setStyleSheet("QScrollArea { border: none; background: transparent; }")

        layout.addWidget(scroll, 1)

    def create_dashboard_footer(self, layout):
        """Create the dashboard footer - professional status bar with rounded corners"""
        footer_widget = QFrame()
        footer_widget.setFixedHeight(40)
        footer_widget.setStyleSheet(f"""
            QFrame {{
                background-color: {PALETTE['panel']};
                border-top: 1px solid {PALETTE['border']};
                border-bottom-left-radius: 12px;
                border-bottom-right-radius: 12px;
            }}
        """)
        footer_layout = QHBoxLayout(footer_widget)
        footer_layout.setContentsMargins(20, 8, 20, 8)
        footer_layout.setSpacing(0)

        self.hub_status = QLabel("✓ Ready. All systems operational. Select any standalone tool to launch. All scripts operate independently.")
        self.hub_status.setStyleSheet(f"color: {PALETTE['muted']}; font-size: 12px; font-weight: 500; background: transparent;")

        footer_author = QLabel("Sebastian Januchowski @ polsoft.ITS(TM) Dev")
        footer_author.setStyleSheet(f"color: {PALETTE['muted']}; font-size: 11px; background: transparent;")

        footer_layout.addWidget(self.hub_status)
        footer_layout.addStretch()
        footer_layout.addWidget(footer_author)

        layout.addWidget(footer_widget)

    def load_splash_image(self):
        """Load splash image if available (identical to original)"""
        image_path = self.image_path
        if not image_path:
            image_path = self.script_dir / "splash.jpg"

        if image_path and Path(image_path).exists():
            try:
                pixmap = QPixmap(str(image_path))
                if not pixmap.isNull():
                    scaled_pixmap = pixmap.scaled(
                        860, 610,
                        Qt.KeepAspectRatioByExpanding,
                        Qt.SmoothTransformation
                    )
                    self.splash_image.setPixmap(scaled_pixmap)
                    self.splash_image.show()
                    self.vector_fallback.hide()
                    return
            except Exception as e:
                print(f"Image loading failed: {e}")

        # Show fallback
        self.splash_image.hide()
        self.vector_fallback.show()

    def setup_connections(self):
        """Setup signal connections (identical to original)"""
        # Splash controls
        self.btn_open_hub.clicked.connect(self.transition_to_dashboard)

        # Dashboard controls
        self.btn_close.clicked.connect(self.close)
        self.btn_refresh.clicked.connect(self.refresh_dashboard)
        self.btn_elevate.clicked.connect(self.elevate)

        # Links
        self.github_btn.clicked.connect(self.on_github_click)
        self.email_btn.clicked.connect(self.on_email_click)
        self.btn_about.clicked.connect(self.on_about_click)

        # Window dragging
        self.outer_border.mousePressEvent = self.on_drag_start
        self.outer_border.mouseMoveEvent = self.on_drag_move

        # Keyboard shortcut: Ctrl+R -> Refresh
        QShortcut(QKeySequence("Ctrl+R"), self, self.refresh_dashboard)

        # Splash click
        self.view_splash.mousePressEvent = self.on_splash_click

    def show_centered(self):
        """Center window on screen (identical to WindowStartupLocation=CenterScreen)"""
        frame = self.frameGeometry()
        screen = QApplication.desktop().screenGeometry()
        center = screen.center()
        frame.moveCenter(center)
        self.move(frame.topLeft())

    def start_splash_timer(self):
        """Start the splash countdown timer (identical to original)"""
        if self.duration_sec <= 0:
            self.progress_bar.hide()
            return

        self.timer_total_steps = 100
        interval = int((self.duration_sec * 1000) / self.timer_total_steps)
        self.timer_current_step = 0

        self.splash_timer = QTimer()
        self.splash_timer.timeout.connect(self.on_timer_tick)
        self.splash_timer.start(interval)

    def on_timer_tick(self):
        """Handle timer tick (identical to original)"""
        self.timer_current_step += 1
        remaining = 100 - self.timer_current_step
        self.progress_bar.setValue(max(0, remaining))

        if self.timer_current_step >= self.timer_total_steps:
            if self.splash_timer:
                self.splash_timer.stop()
                self.splash_timer = None
            self.transition_to_dashboard()

    def on_splash_click(self, event):
        """Handle splash screen click (identical to MouseLeftButtonDown)"""
        self.transition_to_dashboard()

    def transition_to_dashboard(self):
        """Transition from splash to dashboard (identical to original)"""
        if self.in_dashboard:
            return
        self.in_dashboard = True

        if self.splash_timer:
            self.splash_timer.stop()
            self.splash_timer = None

        if self.splash_only:
            self.close()
            return

        # Hide splash, show dashboard
        self.view_splash.hide()
        self.view_dashboard.show()
        self.update_preflight()
        self.populate_dashboard()

    def update_preflight(self):
        """Update system status information (identical to original)"""
        # 1. Admin status (enhanced modern colors)
        try:
            is_admin = self.is_admin()
            if is_admin:
                self.admin_badge.setStyleSheet("""
                    QLabel {
                        background-color: #1e3a2f;
                        color: #2ecc71;
                        font-size: 10px;
                        font-weight: bold;
                        padding: 3px 8px;
                        border-radius: 4px;
                    }
                """)
                self.admin_badge.setText("ADMINISTRATOR")
                self.btn_elevate.hide()
            else:
                self.admin_badge.setStyleSheet("""
                    QLabel {
                        background-color: #3a2a1e;
                        color: #ff8c42;
                        font-size: 10px;
                        font-weight: bold;
                        padding: 3px 8px;
                        border-radius: 4px;
                    }
                """)
                self.admin_badge.setText("STANDARD USER")
                self.btn_elevate.show()
        except Exception as e:
            print(f"Admin check failed: {e}")

        # 2. Network status - async, aby nie blokować GUI
        self.net_status.setText("CHECKING NET")
        self.check_network_async()

        # 3. PS Version (Python version instead)
        py_ver = f"Python {sys.version_info.major}.{sys.version_info.minor}"
        self.ps_version.setText(py_ver)

        # 4. Disk space
        try:
            free_gb = round(shutil.disk_usage(str(self.script_dir)).free / (1024**3), 1)
            drive = str(self.script_dir)[:2] if sys.platform == "win32" else "/"
            self.disk_space.setText(f"{drive}: {free_gb} GB Free")
        except Exception as e:
            print(f"Disk space check failed: {e}")
            self.disk_space.setText("Disk Ready")

    def check_network_async(self):
        """Async network check — nie blokuje wątku GUI"""
        from concurrent.futures import ThreadPoolExecutor

        def work():
            try:
                import socket
                socket.create_connection(("8.8.8.8", 53), timeout=2)
                return True
            except Exception:
                return False

        fut = ThreadPoolExecutor(max_workers=1).submit(work)
        fut.add_done_callback(
            lambda f: QTimer.singleShot(0, lambda: self.apply_network_result(f.result()))
        )

    def apply_network_result(self, online: bool):
        """Zastosuj wynik checku sieci (wywoływane w wątku GUI)"""
        if online:
            self.net_status.setStyleSheet("""
                QLabel {
                    background-color: #21262d;
                    color: #2ecc71;
                    font-size: 10px;
                    font-weight: bold;
                    padding: 3px 8px;
                    border-radius: 4px;
                }
            """)
            self.net_status.setText("ONLINE")
            self.status_ok.setText("SYSTEM STATUS OK")
            self.status_ok.setStyleSheet("color: #2ecc71; font-size: 10px; font-weight: bold; background: transparent;")
        else:
            self.net_status.setStyleSheet("""
                QLabel {
                    background-color: #21262d;
                    color: #e74c3c;
                    font-size: 10px;
                    font-weight: bold;
                    padding: 3px 8px;
                    border-radius: 4px;
                }
            """)
            self.net_status.setText("OFFLINE")
            self.status_ok.setText("LIMITED — NO NETWORK")
            self.status_ok.setStyleSheet("color: #ff8c42; font-size: 10px; font-weight: bold; background: transparent;")

    def populate_dashboard(self):
        """Populate the tools grid (identical to original)"""
        # Clear existing
        for i in reversed(range(self.tools_layout.count())):
            self.tools_layout.itemAt(i).widget().setParent(None)

        # Add tool cards (3x3 grid)
        row, col = 0, 0
        for tool in self.tools_catalog:
            card = self.create_tool_card(tool)
            self.tools_layout.addWidget(card, row, col)
            col += 1
            if col >= 3:
                col = 0
                row += 1

    def create_tool_card(self, tool):
        """Create a tool card widget (enhanced modern colors)"""
        card = QFrame()
        card.setAttribute(Qt.WA_StyledBackground, True)
        card.setStyleSheet(f"""
            QFrame {{
                background-color: {PALETTE['card']};
                border: 1px solid {PALETTE['border']};
                border-radius: 10px;
            }}
            QFrame:hover {{
                border-color: {PALETTE['accent']};
                background-color: {PALETTE['panel']};
            }}
        """)
        card.setFixedHeight(125)

        shadow = QGraphicsDropShadowEffect(self)
        shadow.setBlurRadius(18)
        shadow.setOffset(0, 3)
        shadow.setColor(QColor(0, 0, 0, 45))
        card.setGraphicsEffect(shadow)

        layout = QVBoxLayout(card)
        layout.setContentsMargins(12, 10, 12, 10)
        layout.setSpacing(6)

        # Header Row (Badge & Tool Name)
        header = QHBoxLayout()
        header.setSpacing(0)

        name = QLabel(tool["name"])
        name.setStyleSheet(f"color: {tool['color']}; font-size: 14px; font-weight: bold; background: transparent;")
        header.addWidget(name)

        header.addStretch()

        badge = QLabel(tool["badge"])
        badge.setStyleSheet(f"""
            QLabel {{
                background-color: {PALETTE['bg']};
                color: {tool['color']};
                font-size: 9px;
                font-weight: bold;
                padding: 2px 6px;
                border-radius: 4px;
            }}
        """)
        header.addWidget(badge)

        layout.addLayout(header)

        # Description (enhanced modern color)
        desc = QLabel(tool["desc"])
        desc.setStyleSheet(f"color: {PALETTE['muted']}; font-size: 11px; background: transparent;")
        desc.setWordWrap(True)
        layout.addWidget(desc)
        layout.addSpacing(2)

        # Action Row (Status & Launch Button)
        action = QHBoxLayout()
        action.setSpacing(0)

        script_path = self.script_dir / tool["file"]
        is_found = script_path.exists()

        status = QLabel("READY" if is_found else "MISSING")
        status.setStyleSheet(f"""
            QLabel {{
                color: {"#2ecc71" if is_found else "#e74c3c"};
                font-size: 10px;
                background: transparent;
            }}
        """)
        action.addWidget(status)

        action.addStretch()

        launch_btn = QPushButton("Launch")
        launch_btn.setFixedSize(72, 26)
        launch_btn.setEnabled(is_found)
        if is_found:
            launch_btn.setStyleSheet(f"""
                QPushButton {{
                    background-color: {tool['color']};
                    color: #0d1117;
                    font-size: 11px;
                    border-radius: 6px;
                    border: none;
                }}
                QPushButton:hover {{
                    background-color: #0d1117;
                    color: {tool['color']};
                }}
            """)
            launch_btn.clicked.connect(lambda: self.launch_tool(script_path, tool["name"]))
        else:
            launch_btn.setStyleSheet("""
                QPushButton {
                    background-color: #21262d;
                    color: #8b949e;
                    font-size: 11px;
                    border-radius: 6px;
                    border: none;
                }
            """)

        action.addWidget(launch_btn)
        layout.addLayout(action)

        return card

    def launch_tool(self, script_path, tool_name):
        """Launch a PowerShell script with hidden terminal window"""
        self.hub_status.setText(f"Launching {tool_name}...")

        try:
            # Use STARTUPINFO to hide the console window on Windows
            if sys.platform == "win32":
                startupinfo = subprocess.STARTUPINFO()
                startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
                startupinfo.wShowWindow = subprocess.SW_HIDE

                subprocess.Popen(
                    ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", str(script_path)],
                    startupinfo=startupinfo,
                    creationflags=subprocess.CREATE_NO_WINDOW
                )
            else:
                # On non-Windows, run normally
                subprocess.Popen(
                    ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", str(script_path)]
                )
        except Exception as e:
            QMessageBox.warning(self, "Notice", f"Script not found: {script_path}\n{str(e)}")

    def refresh_dashboard(self):
        """Refresh the dashboard (identical to original)"""
        self.update_preflight()
        self.populate_dashboard()
        self.hub_status.setText("Catalog and environment status refreshed.")

    def elevate(self):
        """Restart as administrator via UAC prompt"""
        try:
            if sys.platform == "win32":
                import ctypes
                params = f'"{os.path.abspath(__file__)}" -SkipSplash'
                # ShellExecuteW z verb "runas" wywołuje prawdziwy monit UAC
                ret = ctypes.windll.shell32.ShellExecuteW(
                    None, "runas", sys.executable, params, None, 1  # 1 = SW_SHOWNORMAL
                )
                if ret > 32:            # >32 = sukces
                    self.close()
                else:
                    QMessageBox.warning(self, "Elevation Error",
                                        f"UAC odrzucił podniesienie uprawnień (kod {ret}).")
            else:
                QMessageBox.information(self, "Info", "Elewacja dostępna tylko na Windows.")
        except Exception as e:
            QMessageBox.warning(self, "Elevation Error", f"Could not elevate: {str(e)}")

    def on_github_click(self):
        """Handle GitHub button click - opens GitHub page in browser"""
        QDesktopServices.openUrl(QUrl(self.app_github))
        self.hub_status.setText(f"[+] Opening GitHub: {self.app_github}")

    def on_email_click(self):
        """Handle email button click - opens default email client and copies to clipboard"""
        # Open default email client
        QDesktopServices.openUrl(QUrl(f"mailto:{self.app_email}"))
        # Also copy to clipboard as fallback
        clipboard = QApplication.clipboard()
        clipboard.setText(self.app_email)
        self.hub_status.setText(f"[+] Email client opened, {self.app_email} copied to clipboard!")

    def on_about_click(self):
        """Handle about button click - shows custom styled about window matching app theme"""
        # Create custom dialog
        about_dialog = QDialog(self)
        about_dialog.setWindowTitle("O programie")
        about_dialog.setFixedSize(450, 380)
        about_dialog.setWindowFlags(Qt.Dialog | Qt.MSWindowsFixedSizeDialogHint)
        
        # Main layout
        layout = QVBoxLayout(about_dialog)
        layout.setContentsMargins(30, 30, 30, 30)
        layout.setSpacing(20)
        
        # Set dialog background style matching the app's dark theme
        about_dialog.setStyleSheet(f"""
            QDialog {{
                background-color: {PALETTE['bg']};
                border: 1px solid {PALETTE['border']};
                border-radius: 12px;
            }}
            QLabel {{
                color: {PALETTE['text']};
                font-family: 'Segoe UI', system-ui, sans-serif;
            }}
        """)
        
        # App title (polsoft.ITS in signature blue)
        title_label = QLabel("polsoft.ITS(TM)")
        title_label.setStyleSheet("""
            font-size: 28px;
            font-weight: 900;
            color: #00d4ff;
            letter-spacing: 2px;
        """)
        title_label.setAlignment(Qt.AlignCenter)
        layout.addWidget(title_label)
        
        # Subtitle
        subtitle_label = QLabel("Developers Tools Hub")
        subtitle_label.setStyleSheet(f"""
            font-size: 16px;
            color: {PALETTE['muted']};
            margin-bottom: 10px;
        """)
        subtitle_label.setAlignment(Qt.AlignCenter)
        layout.addWidget(subtitle_label)
        
        # Separator line
        separator = QFrame()
        separator.setFrameShape(QFrame.HLine)
        separator.setStyleSheet(f"background-color: {PALETTE['border']};")
        layout.addWidget(separator)
        
        # Info container with details
        info_layout = QVBoxLayout()
        info_layout.setSpacing(12)
        
        # Version
        # Version (odczyt z pliku VERSION, fallback 1.0.0)
        try:
            app_version = (self.script_dir / "VERSION").read_text(encoding="utf-8").strip() or "1.0.0"
        except Exception:
            app_version = "1.0.0"
        version_label = QLabel(f"Wersja: <span style='color:#00d4ff;'>{app_version}</span>")
        version_label.setTextFormat(Qt.RichText)
        version_label.setAlignment(Qt.AlignCenter)
        info_layout.addWidget(version_label)
        
        # Author
        author_label = QLabel(f"Autor: <span style='color:#ff8c42;'>{self.app_author}</span>")
        author_label.setTextFormat(Qt.RichText)
        author_label.setAlignment(Qt.AlignCenter)
        info_layout.addWidget(author_label)
        
        # Email
        email_label = QLabel(f"Email: <span style='color:#ff8c42;'>{self.app_email}</span>")
        email_label.setTextFormat(Qt.RichText)
        email_label.setAlignment(Qt.AlignCenter)
        info_layout.addWidget(email_label)
        
        # GitHub
        github_label = QLabel(f"GitHub: <span style='color:#ff8c42;'>{self.app_github.replace('https://', '')}</span>")
        github_label.setTextFormat(Qt.RichText)
        github_label.setAlignment(Qt.AlignCenter)
        info_layout.addWidget(github_label)
        
        layout.addLayout(info_layout)
        
        # Copyright
        copyright_label = QLabel("© 2026 polsoft.ITS. Wszelkie prawa zastrzeżone.")
        copyright_label.setStyleSheet("""
            font-size: 11px;
            color: #484f58;
            margin-top: 15px;
        """)
        copyright_label.setAlignment(Qt.AlignCenter)
        layout.addWidget(copyright_label)
        
        # Close button
        close_btn = QPushButton("Zamknij")
        close_btn.setFixedSize(120, 36)
        close_btn.setStyleSheet("""
            QPushButton {
                background-color: #21262d;
                color: #00d4ff;
                font-size: 13px;
                font-weight: bold;
                border-radius: 6px;
                border: 1px solid #30363d;
            }
            QPushButton:hover {
                background-color: #30363d;
                border-color: #00d4ff;
            }
        """)
        close_btn.clicked.connect(about_dialog.accept)
        
        btn_layout = QHBoxLayout()
        btn_layout.addStretch()
        btn_layout.addWidget(close_btn)
        btn_layout.addStretch()
        layout.addLayout(btn_layout)
        
        # Show the dialog
        about_dialog.exec_()

    def on_drag_start(self, event):
        """Handle window drag start (identical to DragMove)"""
        if event.button() == Qt.LeftButton:
            self.drag_pos = event.globalPos() - self.frameGeometry().topLeft()
            event.accept()

    def on_drag_move(self, event):
        """Handle window drag move (identical to DragMove)"""
        if event.buttons() == Qt.LeftButton and self.drag_pos:
            self.move(event.globalPos() - self.drag_pos)
            event.accept()

    def is_admin(self):
        """Check if running as administrator (Windows only, identical to original)"""
        try:
            import ctypes
            return ctypes.windll.shell32.IsUserAnAdmin() != 0
        except:
            return False

    def keyPressEvent(self, event):
        """Handle keyboard input (identical to original KeyDown)"""
        if not self.in_dashboard:
            if event.key() in (Qt.Key_Space, Qt.Key_Return):
                self.transition_to_dashboard()
            elif event.key() == Qt.Key_Escape:
                self.close()
        else:
            if event.key() == Qt.Key_Escape:
                self.close()


def main():
    """Main entry point with argument parsing (identical to PowerShell parameters)"""
    parser = argparse.ArgumentParser(description="splashScreen - polsoft.ITS(TM) Developers Splash Screen & Tools Hub")
    parser.add_argument("-DurationSec", type=int, default=3, help="Seconds to display splash screen")
    parser.add_argument("-SplashOnly", action="store_true", help="Show splash only and exit")
    parser.add_argument("-SkipSplash", action="store_true", help="Skip splash and open dashboard directly")
    parser.add_argument("-ImagePath", type=str, help="Custom path to splash image")

    args = parser.parse_args()

    app = QApplication(sys.argv)
    app.setStyle("Fusion")

    # Set dark theme
    app.setPalette(app.style().standardPalette())

    window = SplashScreen(
        duration_sec=args.DurationSec,
        splash_only=args.SplashOnly,
        skip_splash=args.SkipSplash,
        image_path=args.ImagePath
    )

    sys.exit(app.exec_())


if __name__ == "__main__":
    main()