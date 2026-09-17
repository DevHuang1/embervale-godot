package com.embervale.revenuecat

import android.util.Log
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesError
import com.revenuecat.purchases.interfaces.LogInCallback
import com.revenuecat.purchases.interfaces.ReceiveCustomerInfoCallback
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONArray
import org.json.JSONObject

/**
 * Read-only RevenueCat bridge for Embervale.
 *
 * Money never moves through this plugin: purchases happen on the hosted
 * RevenueCat funnel (web checkout), and this plugin only reports which
 * entitlements the customer owns so the game can claim them exactly once.
 * That keeps the exported client free of any provider secret — it is
 * configured with the PUBLIC SDK key, which is designed to ship.
 */
class RevenueCatBridgePlugin(godot: Godot) : GodotPlugin(godot) {

    private val activeEntitlementsSignal =
        SignalInfo(SIGNAL_ACTIVE_ENTITLEMENTS, String::class.java)
    private val errorSignal = SignalInfo(SIGNAL_ERROR, String::class.java, String::class.java)

    /**
     * Configuration is applied on the UI thread, so a read issued in the same
     * frame can arrive first. Such a read is queued and served as soon as the
     * SDK is ready instead of failing with a spurious `not_configured`.
     */
    private var configureRequested = false
    private var pendingFetch = false

    override fun getPluginName(): String = PLUGIN_NAME

    override fun getPluginSignals(): Set<SignalInfo> =
        setOf(activeEntitlementsSignal, errorSignal)

    /**
     * Configures the SDK with the public SDK key and the game's stable App User
     * ID. Safe to call more than once: the first configuration wins, so a
     * repeated autoload setup cannot create a second customer.
     */
    @UsedByGodot
    fun configure(apiKey: String, appUserId: String) {
        val key = apiKey.trim()
        if (key.isEmpty()) {
            emitError("invalid_key", "an empty SDK key cannot configure RevenueCat")
            return
        }
        configureRequested = true
        runOnUiThread {
            try {
                if (Purchases.isConfigured) {
                    Log.i(TAG, "configure ignored: the SDK is already configured")
                    return@runOnUiThread
                }
                val activity = getActivity()
                if (activity == null) {
                    emitError("configure_failed", "no Android activity is available yet")
                    return@runOnUiThread
                }
                Purchases.logLevel = LogLevel.INFO
                val builder = PurchasesConfiguration.Builder(activity, key)
                val trimmedUser = appUserId.trim()
                if (trimmedUser.isNotEmpty()) {
                    builder.appUserID(trimmedUser)
                }
                Purchases.configure(builder.build())
                Log.i(TAG, "configured (app user id supplied: ${trimmedUser.isNotEmpty()})")
                if (pendingFetch) {
                    pendingFetch = false
                    getActiveEntitlements()
                }
            } catch (throwable: Throwable) {
                emitError("configure_failed", throwable.message ?: "unknown configure failure")
            }
        }
    }

    @UsedByGodot
    fun isConfigured(): Boolean = Purchases.isConfigured

    /**
     * Fetches the customer's current entitlements. The cache is invalidated
     * first so a purchase completed on the web is visible immediately.
     */
    @UsedByGodot
    fun getActiveEntitlements() {
        if (!Purchases.isConfigured) {
            if (configureRequested) {
                // The SDK is still coming up: serve this read once it is ready.
                pendingFetch = true
            } else {
                emitError("not_configured", "configure must be called before reading entitlements")
            }
            return
        }
        try {
            Purchases.sharedInstance.invalidateCustomerInfoCache()
            Purchases.sharedInstance.getCustomerInfo(object : ReceiveCustomerInfoCallback {
                override fun onReceived(customerInfo: CustomerInfo) {
                    emitActiveEntitlements(customerInfo)
                }

                override fun onError(error: PurchasesError) {
                    emitProviderError(error)
                }
            })
        } catch (throwable: Throwable) {
            emitError("provider_error", throwable.message ?: "unknown customer info failure")
        }
    }

    @UsedByGodot
    fun logIn(appUserId: String) {
        val trimmed = appUserId.trim()
        if (trimmed.isEmpty()) {
            emitError("invalid_customer_id", "an empty App User ID cannot be used")
            return
        }
        if (!Purchases.isConfigured) {
            emitError("not_configured", "configure must be called before logging in")
            return
        }
        Purchases.sharedInstance.logIn(trimmed, object : LogInCallback {
            override fun onReceived(customerInfo: CustomerInfo, created: Boolean) {
                emitActiveEntitlements(customerInfo)
            }

            override fun onError(error: PurchasesError) {
                emitProviderError(error)
            }
        })
    }

    @UsedByGodot
    fun logOut() {
        if (!Purchases.isConfigured) {
            emitError("not_configured", "configure must be called before logging out")
            return
        }
        Purchases.sharedInstance.logOut(object : ReceiveCustomerInfoCallback {
            override fun onReceived(customerInfo: CustomerInfo) {
                emitActiveEntitlements(customerInfo)
            }

            override fun onError(error: PurchasesError) {
                emitProviderError(error)
            }
        })
    }

    /**
     * Emits the active entitlements in the same shape as RevenueCat's REST
     * `active_entitlements` list, so the game parses one contract for every
     * authority. A null expiry means the entitlement never expires.
     */
    private fun emitActiveEntitlements(customerInfo: CustomerInfo) {
        val items = JSONArray()
        for ((identifier, info) in customerInfo.entitlements.active) {
            val row = JSONObject()
            row.put("entitlement_id", identifier)
            val expiration = info.expirationDate
            if (expiration == null) {
                row.put("expires_at", JSONObject.NULL)
            } else {
                row.put("expires_at", expiration.time)
            }
            items.put(row)
        }
        val payload = JSONObject()
            .put("object", "list")
            .put("source", SOURCE_NATIVE)
            .put("items", items)
            .toString()
        GodotPlugin.emitSignal(godot, PLUGIN_NAME, activeEntitlementsSignal, payload)
    }

    private fun emitProviderError(error: PurchasesError) {
        val code = error.code.name
        Log.w(TAG, "RevenueCat error: $code — ${error.message}")
        emitError(code, error.message)
    }

    private fun emitError(code: String, message: String) {
        GodotPlugin.emitSignal(godot, PLUGIN_NAME, errorSignal, code, message)
    }

    companion object {
        private const val TAG = "RevenueCatBridge"
        private const val PLUGIN_NAME = "RevenueCatBridge"
        private const val SOURCE_NATIVE = "revenuecat_native"
        const val SIGNAL_ACTIVE_ENTITLEMENTS = "active_entitlements"
        const val SIGNAL_ERROR = "customer_info_error"
    }
}
