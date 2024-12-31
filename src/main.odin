package vulkan_playground

import "base:runtime"
import "core:fmt"
import "core:mem"
import "vendor:glfw"
import vk "vendor:vulkan"

window: glfw.WindowHandle

Vulkan_Context :: struct {
    instance:        vk.Instance,
    physical_device: vk.PhysicalDevice,
    device:          vk.Device,
    surface:         vk.SurfaceKHR,
    graphics_queue:  vk.Queue,
    present_queue:   vk.Queue,
}

Queue_Family_Indices :: struct {
    present_family:  u32,
    graphics_family: u32,
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

        if _, ok := get_queue_family_indices(d); ok {
            vk_context.physical_device = d
            return
        }
    }
    assert(false)
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

