package com.srkstudios.dynamic_app_icon_changer

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.test.Test
import org.mockito.Mockito

internal class DynamicAppIconChangerPluginTest {
    @Test
    fun supportsAlternateIconsReturnsTrue() {
        val plugin = DynamicAppIconChangerPlugin()
        val call = MethodCall("supportsAlternateIcons", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)
        Mockito.verify(mockResult).success(true)
    }
}
