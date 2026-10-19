package vn.hoadoninsight.hoadon_insight

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val bankPackages = mapOf(
        "mb" to "com.mbmobile",
        "icb" to "com.vietinbank.ipay",
        "bidv" to "com.vnpay.bidv",
        "acb" to "mobile.acb.com.vn",
        "ocb" to "vn.com.ocb.awe",
        "vcb" to "com.VCB",
        "tcb" to "vn.com.techcombank.bb.app",
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hoadoninsight/bank_apps")
            .setMethodCallHandler { call, result ->
                if (call.method == "openBankApp") {
                    val packageName = bankPackages[call.argument<String>("appId")]
                    if (packageName == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val intent = packageManager.getLaunchIntentForPackage(packageName)
                    try {
                        if (intent == null || intent.resolveActivity(packageManager) == null) {
                            result.success(false)
                        } else {
                            startActivity(intent)
                            result.success(true)
                        }
                    } catch (_: ActivityNotFoundException) {
                        result.success(false)
                    } catch (_: SecurityException) {
                        result.success(false)
                    }
                    return@setMethodCallHandler
                }
                if (call.method == "openPaymentPage") {
                    val uri = Uri.parse(call.argument<String>("url") ?: "")
                    if (uri.scheme != "https" || uri.host != "dl.vietqr.io" || uri.path != "/pay") {
                        result.error("invalid_url", "Invalid payment page", null)
                        return@setMethodCallHandler
                    }
                    val providers = packageManager.queryIntentServices(
                        Intent("android.support.customtabs.action.CustomTabsService"), 0,
                    ).map { it.serviceInfo.packageName }
                    val viewIntent = Intent(Intent.ACTION_VIEW, uri)
                    viewIntent.addCategory(Intent.CATEGORY_BROWSABLE)
                    val defaultBrowser = packageManager.resolveActivity(
                        viewIntent, PackageManager.MATCH_DEFAULT_ONLY,
                    )?.activityInfo?.packageName
                    val handlers = packageManager.queryIntentActivities(
                        viewIntent, PackageManager.MATCH_DEFAULT_ONLY,
                    ).map { it.activityInfo.packageName }.toSet()
                    val knownBrowsers = listOf(
                        "com.android.chrome",
                        "com.sec.android.app.sbrowser",
                        "com.huawei.browser",
                        "com.android.browser",
                        "com.heytap.browser",
                        "com.vivo.browser",
                        "org.mozilla.firefox",
                        "com.microsoft.emmx",
                        "com.brave.browser",
                        "com.opera.browser",
                    )
                    val browser = providers.firstOrNull { it == defaultBrowser }
                        ?: providers.sorted().firstOrNull()
                        ?: (listOfNotNull(defaultBrowser) + knownBrowsers)
                            .firstOrNull { it in handlers && it in knownBrowsers }
                    if (browser == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    // A pinned Custom Tabs provider avoids Android's generic URL chooser.
                    viewIntent.setPackage(browser)
                    if (browser in providers) {
                        viewIntent.putExtras(Bundle().apply {
                            putBinder("android.support.customtabs.extra.SESSION", null)
                        })
                    }
                    try {
                        startActivity(viewIntent)
                        result.success(true)
                    } catch (_: ActivityNotFoundException) {
                        result.success(false)
                    } catch (_: SecurityException) {
                        result.success(false)
                    }
                    return@setMethodCallHandler
                }
                if (call.method != "installedBankAppIds") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val installed = bankPackages.filterValues { packageName ->
                    try {
                        packageManager.getApplicationInfo(packageName, 0).enabled
                    } catch (_: android.content.pm.PackageManager.NameNotFoundException) {
                        false
                    }
                }.keys.toList()
                result.success(installed)
            }
    }
}
