package vulkan_playground

import "base:runtime"
import "core:fmt"
import "core:math/bits"
import "core:mem"
import "vendor:glfw"
import vk "vendor:vulkan"

window: glfw.WindowHandle

Vulkan_Context :: struct {
    instance:               vk.Instance,
    physical_device:        vk.PhysicalDevice,
    device:                 vk.Device,
    surface:                vk.SurfaceKHR,
    graphics_queue:         vk.Queue,
    present_queue:          vk.Queue,
    swap_chain:             vk.SwapchainKHR,
    swap_chain_extent:      vk.Extent2D,
    swap_chain_format:      vk.Format,
    swap_chain_images:      [dynamic]vk.Image,
    swap_chain_image_views: [dynamic]vk.ImageView,
}

Queue_Family_Indices :: struct {
    present_family:  u32,
    graphics_family: u32,
}

Swap_Chain_Support_Details :: struct {
    capabilities: vk.SurfaceCapabilitiesKHR,
    formats:      [dynamic]vk.SurfaceFormatKHR,
    presentModes: [dynamic]vk.PresentModeKHR,
}

vk_context: Vulkan_Context

VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"}
DEVICE_EXTENSIONS := [?]cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}

init_window :: proc() {
    glfw.Init()
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
    glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)
    window = glfw.CreateWindow(800, 600, "Vulkan Playground", nil, nil)
}

init_vulkan :: proc() {
    context.user_ptr = &vk_context.instance

    get_proc_address :: proc(p: rawptr, name: cstring) {
        (cast(^rawptr)p)^ = glfw.GetInstanceProcAddress((^vk.Instance)(context.user_ptr)^, name)
    }

    vk.load_proc_addresses(get_proc_address)
    create_instance()
    vk.load_proc_addresses(get_proc_address)

    create_surface()
    pick_physical_device()
    create_logical_device()
    create_swap_chain()
    create_image_views()
}

create_instance :: proc() {
    app_info: vk.ApplicationInfo
    app_info.sType = .APPLICATION_INFO
    app_info.pApplicationName = "Hello Triangle"
    app_info.applicationVersion = vk.MAKE_VERSION(1, 0, 0)
    app_info.pEngineName = "NCE"
    app_info.engineVersion = vk.MAKE_VERSION(1, 0, 0)
    app_info.apiVersion = vk.API_VERSION_1_0

    create_info: vk.InstanceCreateInfo
    create_info.sType = .INSTANCE_CREATE_INFO
    create_info.pApplicationInfo = &app_info

    // extension_count: u32 = 0
    // extensions: [^]

    extensions := glfw.GetRequiredInstanceExtensions()
    create_info.enabledExtensionCount = cast(u32)len(extensions)
    create_info.ppEnabledExtensionNames = raw_data(extensions)
    when ODIN_DEBUG {
        create_info.enabledLayerCount = cast(u32)len(VALIDATION_LAYERS)
        create_info.ppEnabledLayerNames = &VALIDATION_LAYERS[0]
    } else {
        create_info.enabledLayerCount = 0
    }

    result := vk.CreateInstance(&create_info, nil, &vk_context.instance)
    if result != .SUCCESS {
        panic("Unable to create VK instance!")
    }


    n_ext: u32
    vk.EnumerateInstanceExtensionProperties(nil, &n_ext, nil)
    extensions_buff := make([]vk.ExtensionProperties, n_ext)
    defer delete(extensions_buff)
    vk.EnumerateInstanceExtensionProperties(nil, &n_ext, raw_data(extensions_buff))

    for &ext in extensions_buff {
        fmt.println(cast(cstring)&ext.extensionName[0])
    }
}

pick_physical_device :: proc() {
    device_count: u32
    vk.EnumeratePhysicalDevices(vk_context.instance, &device_count, nil)

    physical_device_buffer := make([]vk.PhysicalDevice, device_count)
    defer delete(physical_device_buffer)

    vk.EnumeratePhysicalDevices(vk_context.instance, &device_count, raw_data(physical_device_buffer))

    for &d in physical_device_buffer {
        if !check_device_extension_support(d) {
            continue
        }

        support := query_swap_chain_support(d)
        defer {
            delete(support.formats)
            delete(support.presentModes)
        }

        swap_chain_adequate := len(support.formats) > 0 && len(support.presentModes) > 0

        if !swap_chain_adequate {
            continue
        }

        if _, ok := get_queue_family_indices(d); ok {
            vk_context.physical_device = d
            return
        }
    }
    assert(false)
}

choose_swap_chain_surface_format :: proc(available_formats: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
    for &format in available_formats {
        if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
            return format
        }
    }

    return available_formats[0]
}

/// XXX  Note there's various present mode options, 2 of which are unlocked FR which could result 
/// in tearing. The below code tries to go for triple buffering, and if unavailable goes for FIFO
choose_swap_chain_present_mode :: proc(available_present_modes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
    for &present_mode in available_present_modes {
        if present_mode == .MAILBOX {
            return present_mode
        }
    }
    // Default to FIFO if there's no mailbox (triple buffering)
    return .FIFO
}

// This is the resolution of the swap chain images
choose_swap_extent :: proc(capability: vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {
    if capability.currentExtent.width != bits.U32_MAX {
        return capability.currentExtent
    }

    width, height := glfw.GetFramebufferSize(window)
    actual_extent := vk.Extent2D {
        width  = u32(width),
        height = u32(height),
    }

    actual_extent.width = clamp(actual_extent.width, capability.minImageExtent.width, capability.maxImageExtent.width)
    actual_extent.height = clamp(actual_extent.height, capability.minImageExtent.height, capability.maxImageExtent.height)

    return actual_extent
}

create_swap_chain :: proc() {
    support := query_swap_chain_support(vk_context.physical_device)
    defer {
        delete(support.formats)
        delete(support.presentModes)
    }

    surface_format := choose_swap_chain_surface_format(support.formats[:])
    present_mode := choose_swap_chain_present_mode(support.presentModes[:])
    extent := choose_swap_extent(support.capabilities)

    image_count: u32 = support.capabilities.minImageCount + 1
    if support.capabilities.maxImageCount > 0 && image_count > support.capabilities.maxImageCount {
        image_count = support.capabilities.maxImageCount
    }

    create_info := vk.SwapchainCreateInfoKHR {
        sType            = .SWAPCHAIN_CREATE_INFO_KHR,
        surface          = vk_context.surface,
        minImageCount    = image_count,
        imageFormat      = surface_format.format,
        imageColorSpace  = surface_format.colorSpace,
        imageExtent      = extent,
        imageArrayLayers = 1,
        imageUsage       = {.COLOR_ATTACHMENT}, // Transfer_dst_bit would be used for rendering to an image first
    }

    indices, ok := get_queue_family_indices(vk_context.physical_device)
    assert(ok)

    family_indices := [2]u32{indices.present_family, indices.graphics_family}

    // Only if indices between present and graphics family differ
    // do we need to specify the indices in the create_info struct
    if indices.present_family != indices.graphics_family {
        create_info.imageSharingMode = .CONCURRENT
        create_info.queueFamilyIndexCount = 2
        create_info.pQueueFamilyIndices = raw_data(family_indices[:])
    } else {
        create_info.imageSharingMode = .EXCLUSIVE
        create_info.queueFamilyIndexCount = 0
        create_info.pQueueFamilyIndices = nil
    }

    // Transforms to be applied we'll take the ones from the capabilities
    create_info.preTransform = support.capabilities.currentTransform

    // We always want opaque alpha with the windowing system
    create_info.compositeAlpha = {.OPAQUE}

    create_info.presentMode = present_mode
    create_info.clipped = true

    // create_info.oldSwapchain = vk.NULL // null isn't supported by the binding, but this only counts for resizing windows

    if result := vk.CreateSwapchainKHR(vk_context.device, &create_info, nil, &vk_context.swap_chain); result != .SUCCESS {
        panic("Unable to make swap chain")
    }

    swap_chain_image_count: u32
    vk.GetSwapchainImagesKHR(vk_context.device, vk_context.swap_chain, &swap_chain_image_count, nil)
    vk_context.swap_chain_images = make([dynamic]vk.Image, swap_chain_image_count)
    vk.GetSwapchainImagesKHR(vk_context.device, vk_context.swap_chain, &swap_chain_image_count, raw_data(vk_context.swap_chain_images[:]))

    vk_context.swap_chain_extent = extent
    vk_context.swap_chain_format = surface_format.format
}

get_queue_family_indices :: proc(device: vk.PhysicalDevice) -> (Queue_Family_Indices, bool) {
    queue_family_count: u32
    vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, nil)

    queue_family_buffer := make([]vk.QueueFamilyProperties, queue_family_count)
    defer delete(queue_family_buffer)

    vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, raw_data(queue_family_buffer))

    graphics_idx, present_idx: Maybe(u32)
    completed := false

    for &qf, idx in queue_family_buffer {
        // So long as there's a graphics queue available we're happy
        if .GRAPHICS in qf.queueFlags {
            graphics_idx = cast(u32)idx
        }

        present_supported: b32 = false
        vk.GetPhysicalDeviceSurfaceSupportKHR(device, cast(u32)idx, vk_context.surface, &present_supported)

        if present_supported {
            present_idx = cast(u32)idx
        }

        if graphics_idx != nil && present_idx != nil {
            completed = true
            break
        }
    }

    if completed {
        return {present_family = present_idx.?, graphics_family = graphics_idx.?}, true
    }

    return {}, false
}

create_logical_device :: proc() {
    qfi, _ := get_queue_family_indices(vk_context.physical_device)
    priorities := [?]f32{1.}

    queue_create_info_buff: []vk.DeviceQueueCreateInfo
    defer delete(queue_create_info_buff)

    // Index only needs to be passed once is the index is the same for present/graphics family
    if qfi.present_family == qfi.graphics_family {
        queue_create_info_buff = make([]vk.DeviceQueueCreateInfo, 1)
        queue_create_info_buff[0] = vk.DeviceQueueCreateInfo {
            sType            = .DEVICE_QUEUE_CREATE_INFO,
            queueFamilyIndex = qfi.graphics_family,
            queueCount       = 1,
            pQueuePriorities = raw_data(priorities[:]),
        }
    } else {
        queue_create_info_buff = make([]vk.DeviceQueueCreateInfo, 1)
        queue_create_info_buff[0] = vk.DeviceQueueCreateInfo {
            sType            = .DEVICE_QUEUE_CREATE_INFO,
            queueFamilyIndex = qfi.graphics_family,
            queueCount       = 1,
            pQueuePriorities = raw_data(priorities[:]),
        }
        queue_create_info_buff[1] = vk.DeviceQueueCreateInfo {
            sType            = .DEVICE_QUEUE_CREATE_INFO,
            queueFamilyIndex = qfi.present_family,
            queueCount       = 1,
            pQueuePriorities = raw_data(priorities[:]),
        }

    }

    // Don't need anything special now
    device_features := vk.PhysicalDeviceFeatures{}

    device_create_info := vk.DeviceCreateInfo {
        sType                   = .DEVICE_CREATE_INFO,
        pQueueCreateInfos       = raw_data(queue_create_info_buff[:]),
        queueCreateInfoCount    = cast(u32)len(queue_create_info_buff),
        pEnabledFeatures        = &device_features,
        ppEnabledExtensionNames = raw_data(DEVICE_EXTENSIONS[:]),
        enabledExtensionCount   = len(DEVICE_EXTENSIONS),
    }

    // For compat with older vulkan impls, this is no longer needed on modern 
    // ones since the validation layers aren't split between logical device and 
    // instance
    when ODIN_DEBUG {
        device_create_info.enabledLayerCount = cast(u32)len(VALIDATION_LAYERS)
        device_create_info.ppEnabledLayerNames = &VALIDATION_LAYERS[0]
    } else {
        device_create_info.enabledLayerCount = 0
    }

    result := vk.CreateDevice(vk_context.physical_device, &device_create_info, nil, &vk_context.device)
    if result != .SUCCESS {
        panic("Unable to create VK device!")
    }

    vk.GetDeviceQueue(vk_context.device, qfi.graphics_family, 0, &vk_context.graphics_queue)
    vk.GetDeviceQueue(vk_context.device, qfi.present_family, 0, &vk_context.present_queue)
}

create_surface :: proc() {
    // Way you'd do it if you did it manually, but glfw is heroic and does this for us
    // VkWin32SurfaceCreateInfoKHR createInfo{};
    // createInfo.sType = VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR;
    // createInfo.hwnd = glfwGetWin32Window(window);
    // createInfo.hinstance = GetModuleHandle(nullptr);

    glfw.CreateWindowSurface(vk_context.instance, window, nil, &vk_context.surface)
}

check_device_extension_support :: proc(device: vk.PhysicalDevice) -> bool {
    extension_count: u32
    vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, nil)

    extension_prop_buff := make([]vk.ExtensionProperties, extension_count)
    defer delete(extension_prop_buff)

    vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, raw_data(extension_prop_buff[:]))

    for &ext_name in DEVICE_EXTENSIONS {
        found := false
        for &ext in extension_prop_buff {
            if cstring(&ext.extensionName[0]) == ext_name {
                found = true
                break
            }
        }

        if !found do return false
    }

    return true
}

query_swap_chain_support :: proc(device: vk.PhysicalDevice) -> Swap_Chain_Support_Details {
    details: Swap_Chain_Support_Details

    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, vk_context.surface, &details.capabilities)

    format_count: u32
    vk.GetPhysicalDeviceSurfaceFormatsKHR(device, vk_context.surface, &format_count, nil)

    if format_count != 0 {
        details.formats = make([dynamic]vk.SurfaceFormatKHR, format_count)
        vk.GetPhysicalDeviceSurfaceFormatsKHR(device, vk_context.surface, &format_count, raw_data(details.formats[:]))
    }

    present_mode_count: u32
    vk.GetPhysicalDeviceSurfacePresentModesKHR(device, vk_context.surface, &present_mode_count, nil)

    if present_mode_count != 0 {
        details.presentModes = make([dynamic]vk.PresentModeKHR, present_mode_count)
        vk.GetPhysicalDeviceSurfacePresentModesKHR(device, vk_context.surface, &present_mode_count, raw_data(details.presentModes[:]))
    }

    return details
}

create_image_views :: proc() {
    vk_context.swap_chain_image_views = make([dynamic]vk.ImageView, len(vk_context.swap_chain_images))
    subresource_range :: vk.ImageSubresourceRange {
        aspectMask     = {.COLOR},
        baseMipLevel   = 0,
        levelCount     = 1,
        baseArrayLayer = 0,
        layerCount     = 1,
    }

    // for &sciv, index in vk_context.swap_chain_image_views {
    for index in 0 ..< len(vk_context.swap_chain_image_views) {
        create_info := vk.ImageViewCreateInfo {
            sType            = .IMAGE_VIEW_CREATE_INFO,
            image            = vk_context.swap_chain_images[index],
            viewType         = .D2,
            format           = vk_context.swap_chain_format,
            components       = {.R, .G, .B, .A}, // could map all to 1 channel to make monochrome
            subresourceRange = subresource_range,
        }

        if result := vk.CreateImageView(vk_context.device, &create_info, nil, &vk_context.swap_chain_image_views[index]);
           result != .SUCCESS {
            panic("Unable to create image view for swap chain images")
        }
    }
}

main :: proc() {
    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)

        defer {
            if len(track.allocation_map) > 0 {
                fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }
            }
            if len(track.bad_free_array) > 0 {
                fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
                for entry in track.bad_free_array {
                    fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }
    }

    init_window()
    init_vulkan()

    glfw.SetKeyCallback(window, key_cb)

    defer {
        for &sciv in vk_context.swap_chain_image_views {
            vk.DestroyImageView(vk_context.device, sciv, nil)
        }

        delete(vk_context.swap_chain_image_views)
        delete(vk_context.swap_chain_images)
        vk.DestroySwapchainKHR(vk_context.device, vk_context.swap_chain, nil)
        vk.DestroySurfaceKHR(vk_context.instance, vk_context.surface, nil)
        vk.DestroyDevice(vk_context.device, nil)
        vk.DestroyInstance(vk_context.instance, nil) // instance must be last
        glfw.DestroyWindow(window)
        glfw.Terminate()
    }

    for !glfw.WindowShouldClose(window) {
        glfw.PollEvents()

    }
}


key_cb :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
    context = runtime.default_context()
    fmt.printfln("key %v, action %v, mods %v", key, action, mods)
    if key == glfw.KEY_ESCAPE && action == glfw.PRESS {
        glfw.SetWindowShouldClose(window, true)
    }
}
