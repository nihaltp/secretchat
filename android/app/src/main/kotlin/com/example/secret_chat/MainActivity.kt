// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

package com.nihaltp.secret_chat

import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val hotspotChannel = "secret_chat/hotspot"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, hotspotChannel)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"openHotspotSettings" -> openHotspotSettings(result)
					else -> result.notImplemented()
				}
			}
	}

	private fun openHotspotSettings(result: MethodChannel.Result) {
		try {
			startActivity(Intent("android.settings.TETHER_SETTINGS"))
			result.success(true)
		} catch (_: ActivityNotFoundException) {
			try {
				startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
				result.success(true)
			} catch (_: Exception) {
				result.success(false)
			}
		} catch (_: Exception) {
			result.success(false)
		}
	}
}
