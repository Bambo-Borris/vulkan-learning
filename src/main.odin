package vulkan_playground

import "core:fmt"
import "core:mem"
import "vendor:glfw"
import vk "vendor:vulkan"

window: glfw.WindowHandle
vk_instance: vk.Instance
vk_physical_device: vk.PhysicalDevice

VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"}

init_window :: proc() {
    glfw.Init()
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
    glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)
    window = glfw.CreateWindow(800, 600, "Vulkan Playground", nil, nil)
}

init_vulkan :: proc() {
    context.user_ptr = &vk_instance
    get_proc_address :: proc(p: rawptr, name: cstring) {
        (cast(^rawptr)p)^ = glfw.GetInstanceProcAddress((^vk.Instance)(context.user_ptr)^, name)
    }

    vk.load_proc_addresses(get_proc_address)
    create_instance()
    vk.load_proc_addresses(get_proc_address)

    pick_physical_device()
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
    result := vk.CreateInstance(&create_info, nil, &vk_instance)

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
    vk.EnumeratePhysicalDevices(vk_instance, &device_count, nil)

    physical_device_buffer := make([]vk.PhysicalDevice, device_count)
    defer delete(physical_device_buffer)

    vk.EnumeratePhysicalDevices(vk_instance, &device_count, raw_data(physical_device_buffer))
    for &d in physical_device_buffer {
        device_properties: vk.PhysicalDeviceProperties
        device_features: vk.PhysicalDeviceFeatures

        vk.GetPhysicalDeviceProperties(d, &device_properties)
        vk.GetPhysicalDeviceFeatures(d, &device_features)

        if device_properties.deviceType == .DISCRETE_GPU && device_features.geometryShader {
            vk_physical_device = d
        }
    }

    assert(vk_physical_device != nil)
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

    defer {
        vk.DestroyInstance(vk_instance, nil)
        glfw.DestroyWindow(window)
        glfw.Terminate()
    }

    for !glfw.WindowShouldClose(window) {
        glfw.PollEvents()
    }
}

