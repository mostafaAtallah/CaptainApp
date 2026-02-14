//
//  AppColors.swift
//  CaptainApp
//
//  Created by user on 09/02/2026.
//

import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 08) & 0xff) / 255,
            blue: Double((hex >> 00) & 0xff) / 255,
            opacity: alpha
        )
    }
}

struct AppColors {
    // Primary Colors
    static let primary = Color(hex: 0xFF6C63FF)
    static let primaryLight = Color(hex: 0xFF9D97FF)
    static let primaryDark = Color(hex: 0xFF4A42DB)

    // Secondary Colors
    static let secondary = Color(hex: 0xFFFF6B6B)
    static let secondaryLight = Color(hex: 0xFFFF9999)

    // Status Colors
    static let success = Color(hex: 0xFF4CAF50)
    static let warning = Color(hex: 0xFFFFC107)
    static let error = Color(hex: 0xFFE53935)
    static let info = Color(hex: 0xFF2196F3)

    // Background Colors
    static let background = Color(hex: 0xFFF5F5F5)
    static let surface = Color(hex: 0xFFFFFFFF)
    static let inputFill = Color(hex: 0xFFF0F0F0)

    // Dark Theme Colors
    static let darkBackground = Color(hex: 0xFF121212)
    static let darkSurface = Color(hex: 0xFF1E1E1E)

    // Text Colors
    static let textPrimary = Color(hex: 0xFF1A1A1A)
    static let textSecondary = Color(hex: 0xFF757575)
    static let textHint = Color(hex: 0xFFBDBDBD)
    static let textOnPrimary = Color(hex: 0xFFFFFFFF)

    // Driver Status Colors
    static let online = Color(hex: 0xFF4CAF50)
    static let offline = Color(hex: 0xFF9E9E9E)
    static let busy = Color(hex: 0xFFFF9800)
    

    // Ride Status Colors
    static let rideRequested = Color(hex: 0xFF2196F3)
    static let rideAccepted = Color(hex: 0xFF4CAF50)
    static let rideInProgress = Color(hex: 0xFFFF9800)
    static let rideCompleted = Color(hex: 0xFF4CAF50)
    static let rideCancelled = Color(hex: 0xFFE53935)

    // Map Colors
    static let pickupMarker = Color(hex: 0xFF4CAF50)
    static let dropoffMarker = Color(hex: 0xFFE53935)
    static let routeLine = Color(hex: 0xFF6C63FF)
    
    
    
}
