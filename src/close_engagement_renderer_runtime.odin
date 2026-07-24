package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:math"
import "core:mem"
import "core:testing"
import "core:time"
import vk "vendor:vulkan"
import engine "zelda_engine:engine"
import render3d "zelda_engine:render3d"

combat_3d_init :: proc(ctx: ^engine.Vk_Context) -> bool {
	if combat_3d.initialized do return true
	for i in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(COMBAT_3D_MAX_VERTICES / 2 * size_of(Combat_3D_Line_Instance)), {.VERTEX_BUFFER}, &combat_3d.vertex[i]) do return false; if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(COMBAT_3D_MAX_VERTICES / 2 * size_of(Combat_3D_Line_Instance)), {.VERTEX_BUFFER}, &combat_3d.glow_vertex[i]) do return false; if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(COMBAT_3D_MAX_INSTANCES * size_of(Combat_3D_Instance)), {.VERTEX_BUFFER}, &combat_3d.instance[i]) do return false; if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(COMBAT_3D_MAX_TERRAIN_INSTANCES * size_of(Combat_3D_Terrain_Instance)), {.VERTEX_BUFFER}, &combat_3d.terrain_instance[i]) do return false; if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(COMBAT_3D_MAX_NEBULA_INSTANCES * size_of(Combat_3D_Nebula_Instance)), {.VERTEX_BUFFER}, &combat_3d.nebula_instance[i]) do return false; if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(COMBAT_3D_MAX_CREATURE_GENES * size_of(Combat_3D_Creature_GPU_Gene)), {.STORAGE_BUFFER}, &combat_3d.creature_gene[i]) do return false; if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(size_of(Dark_Render_Globals)), {.UNIFORM_BUFFER}, &combat_3d.dark_globals[i]) do return false}
	combat_3d.vertices = make([dynamic]Combat_3D_Line_Instance, 0, 512)
	combat_3d.glow_vertices = make([dynamic]Combat_3D_Line_Instance, 0, 256)
	combat_3d.instances = make([dynamic]Combat_3D_Instance, 0, COMBAT_3D_MAX_INSTANCES)
	combat_3d.terrain_instances = make(
		[dynamic]Combat_3D_Terrain_Instance,
		0,
		COMBAT_3D_MAX_TERRAIN_INSTANCES,
	)
	combat_3d.nebula_instances = make([dynamic]Combat_3D_Nebula_Instance, 0, COMBAT_3D_MAX_NEBULA_INSTANCES)
	line_vertices := [6]Combat_3D_Line_Vertex {
		{{0, -1}},
		{{1, -1}},
		{{1, 1}},
		{{0, -1}},
		{{1, 1}},
		{{0, 1}},
	}; if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(size_of(line_vertices)), {.VERTEX_BUFFER}, &combat_3d.line_vertex) do return false; mem.copy_non_overlapping(combat_3d.line_vertex.mapped, raw_data(line_vertices[:]), size_of(line_vertices))
	glyphs := combat_3d_build_glyph_meshes(
		
	); defer delete(glyphs); if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(len(glyphs) * size_of(Combat_3D_Glyph_Vertex)), {.VERTEX_BUFFER}, &combat_3d.glyph_vertex) do return false; mem.copy_non_overlapping(combat_3d.glyph_vertex.mapped, raw_data(glyphs[:]), len(glyphs) * size_of(Combat_3D_Glyph_Vertex)); glyph_indices := make([dynamic]u32, len(glyphs)); defer delete(glyph_indices); for &index, i in glyph_indices do index = u32(i); if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(len(glyph_indices) * size_of(u32)), {.INDEX_BUFFER}, &combat_3d.glyph_index) do return false; mem.copy_non_overlapping(combat_3d.glyph_index.mapped, raw_data(glyph_indices[:]), len(glyph_indices) * size_of(u32))
	terrain_mesh, terrain_indices := combat_3d_build_terrain_meshes(
		
	); defer delete(terrain_mesh); defer delete(terrain_indices); if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(len(terrain_mesh) * size_of(Combat_3D_Terrain_Mesh_Vertex)), {.VERTEX_BUFFER}, &combat_3d.terrain_mesh_vertex) do return false; mem.copy_non_overlapping(combat_3d.terrain_mesh_vertex.mapped, raw_data(terrain_mesh[:]), len(terrain_mesh) * size_of(Combat_3D_Terrain_Mesh_Vertex)); if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(len(terrain_indices) * size_of(u32)), {.INDEX_BUFFER}, &combat_3d.terrain_mesh_index) do return false; mem.copy_non_overlapping(combat_3d.terrain_mesh_index.mapped, raw_data(terrain_indices[:]), len(terrain_indices) * size_of(u32))
	vert, frag: engine.Vk_Shader_Module; if !engine.vk_load_shader_module(ctx, "shaders/close_engagement_3d.vert.spv", &vert) do return false; defer engine.vk_destroy_shader_module(ctx, &vert); if !engine.vk_load_shader_module(ctx, "shaders/close_engagement_3d.frag.spv", &frag) do return false; defer engine.vk_destroy_shader_module(ctx, &frag)
	descriptor_bindings := [2]vk.DescriptorSetLayoutBinding {
		{
			binding = 0,
			descriptorType = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags = {.FRAGMENT},
		},
		{
			binding = 1,
			descriptorType = .UNIFORM_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX, .FRAGMENT},
		},
	}
	creature_layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 2,
		pBindings    = raw_data(descriptor_bindings[:]),
	}
	if vk.CreateDescriptorSetLayout(ctx.device, &creature_layout_info, nil, &combat_3d.creature_descriptor_layout) != .SUCCESS do return false
	pool_sizes := [2]vk.DescriptorPoolSize {
		{type = .STORAGE_BUFFER, descriptorCount = engine.MAX_FRAMES_IN_FLIGHT},
		{type = .UNIFORM_BUFFER, descriptorCount = engine.MAX_FRAMES_IN_FLIGHT},
	}
	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = engine.MAX_FRAMES_IN_FLIGHT,
		poolSizeCount = 2,
		pPoolSizes    = raw_data(pool_sizes[:]),
	}
	if vk.CreateDescriptorPool(ctx.device, &pool_info, nil, &combat_3d.creature_descriptor_pool) != .SUCCESS do return false
	layouts: [engine.MAX_FRAMES_IN_FLIGHT]vk.DescriptorSetLayout; for &layout in layouts do layout = combat_3d.creature_descriptor_layout
	allocate_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = combat_3d.creature_descriptor_pool,
		descriptorSetCount = engine.MAX_FRAMES_IN_FLIGHT,
		pSetLayouts        = raw_data(layouts[:]),
	}
	if vk.AllocateDescriptorSets(ctx.device, &allocate_info, raw_data(combat_3d.creature_descriptors[:])) != .SUCCESS do return false
	for i in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {
		buffer_infos := [2]vk.DescriptorBufferInfo {
			{
				buffer = combat_3d.creature_gene[i].handle,
				offset = 0,
				range = vk.DeviceSize(
					COMBAT_3D_MAX_CREATURE_GENES * size_of(Combat_3D_Creature_GPU_Gene),
				),
			},
			{
				buffer = combat_3d.dark_globals[i].handle,
				offset = 0,
				range = vk.DeviceSize(size_of(Dark_Render_Globals)),
			},
		}
		writes := [2]vk.WriteDescriptorSet {
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = combat_3d.creature_descriptors[i],
				dstBinding = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_BUFFER,
				pBufferInfo = &buffer_infos[0],
			},
			{
				sType = .WRITE_DESCRIPTOR_SET,
				dstSet = combat_3d.creature_descriptors[i],
				dstBinding = 1,
				descriptorCount = 1,
				descriptorType = .UNIFORM_BUFFER,
				pBufferInfo = &buffer_infos[1],
			},
		}
		vk.UpdateDescriptorSets(ctx.device, 2, raw_data(writes[:]), 0, nil)
	}
	push_range := vk.PushConstantRange {
		stageFlags = {.VERTEX, .FRAGMENT},
		size       = u32(size_of(Combat_3D_Push)),
	}; layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 1,
		pSetLayouts            = &combat_3d.creature_descriptor_layout,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &push_range,
	}; if vk.CreatePipelineLayout(ctx.device, &layout_info, nil, &combat_3d.pipeline_layout) != .SUCCESS do return false
	stages := [2]vk.PipelineShaderStageCreateInfo {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = vert.handle,
			pName = "main",
		},
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = frag.handle,
			pName = "main",
		},
	}
	bindings := [2]vk.VertexInputBindingDescription {
		{binding = 0, stride = u32(size_of(Combat_3D_Line_Vertex)), inputRate = .VERTEX},
		{binding = 1, stride = u32(size_of(Combat_3D_Line_Instance)), inputRate = .INSTANCE},
	}; attributes := [5]vk.VertexInputAttributeDescription{{location = 0, binding = 0, format = .R32G32_SFLOAT, offset = u32(offset_of(Combat_3D_Line_Vertex, parameter))}, {location = 1, binding = 1, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Combat_3D_Line_Instance, start_position))}, {location = 2, binding = 1, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Combat_3D_Line_Instance, end_position))}, {location = 3, binding = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(Combat_3D_Line_Instance, color))}, {location = 4, binding = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(Combat_3D_Line_Instance, dark_course))}}
	vertex_input := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 2,
		pVertexBindingDescriptions      = raw_data(bindings[:]),
		vertexAttributeDescriptionCount = 5,
		pVertexAttributeDescriptions    = raw_data(attributes[:]),
	}; assembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
	}; viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}; raster := vk.PipelineRasterizationStateCreateInfo {
		sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		cullMode    = {},
		frontFace   = .COUNTER_CLOCKWISE,
		lineWidth   = 1,
	}; multisample := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
	}
	blend_attachment := vk.PipelineColorBlendAttachmentState {
		blendEnable         = true,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp        = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
		alphaBlendOp        = .ADD,
		colorWriteMask      = {.R, .G, .B, .A},
	}; blend := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &blend_attachment,
	}; depth := vk.PipelineDepthStencilStateCreateInfo {
		sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable  = true,
		depthWriteEnable = true,
		depthCompareOp   = .LESS_OR_EQUAL,
	}; dynamic_states := [2]vk.DynamicState {
		.VIEWPORT,
		.SCISSOR,
	}; dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates    = raw_data(dynamic_states[:]),
	}
	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = 2,
		pStages             = raw_data(stages[:]),
		pVertexInputState   = &vertex_input,
		pInputAssemblyState = &assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &raster,
		pMultisampleState   = &multisample,
		pDepthStencilState  = &depth,
		pColorBlendState    = &blend,
		pDynamicState       = &dynamic_state,
		layout              = combat_3d.pipeline_layout,
	}; if !render3d.create_color_pipeline_variants(ctx, &pipeline_info, .D32_SFLOAT, &combat_3d.pipeline) do return false
	contact_vert: engine.Vk_Shader_Module; if !engine.vk_load_shader_module(ctx, "shaders/close_engagement_contact.vert.spv", &contact_vert) do return false; defer engine.vk_destroy_shader_module(ctx, &contact_vert); contact_stages := stages; contact_stages[0].module = contact_vert.handle; contact_bindings := [2]vk.VertexInputBindingDescription{{binding = 0, stride = u32(size_of(Combat_3D_Glyph_Vertex)), inputRate = .VERTEX}, {binding = 1, stride = u32(size_of(Combat_3D_Instance)), inputRate = .INSTANCE}}; contact_attributes := [4]vk.VertexInputAttributeDescription{{location = 0, binding = 0, format = .R32G32_SFLOAT, offset = u32(offset_of(Combat_3D_Glyph_Vertex, position))}, {location = 1, binding = 1, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Combat_3D_Instance, position))}, {location = 2, binding = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(Combat_3D_Instance, facing_scale))}, {location = 3, binding = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(Combat_3D_Instance, color))}}; contact_vertex_input := vertex_input; contact_vertex_input.vertexBindingDescriptionCount = 2; contact_vertex_input.pVertexBindingDescriptions = raw_data(contact_bindings[:]); contact_vertex_input.vertexAttributeDescriptionCount = 4; contact_vertex_input.pVertexAttributeDescriptions = raw_data(contact_attributes[:]); contact_assembly := assembly; contact_assembly.topology = .LINE_LIST; contact_info := pipeline_info; contact_info.pStages = raw_data(contact_stages[:]); contact_info.pVertexInputState = &contact_vertex_input; contact_info.pInputAssemblyState = &contact_assembly; if !render3d.create_color_pipeline_variants(ctx, &contact_info, .D32_SFLOAT, &combat_3d.contact_pipeline) do return false
	terrain_vert, terrain_frag: engine.Vk_Shader_Module; if !engine.vk_load_shader_module(ctx, "shaders/close_engagement_terrain.vert.spv", &terrain_vert) do return false; defer engine.vk_destroy_shader_module(ctx, &terrain_vert); if !engine.vk_load_shader_module(ctx, "shaders/close_engagement_terrain.frag.spv", &terrain_frag) do return false; defer engine.vk_destroy_shader_module(ctx, &terrain_frag); terrain_stages := [2]vk.PipelineShaderStageCreateInfo{{sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.VERTEX}, module = terrain_vert.handle, pName = "main"}, {sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.FRAGMENT}, module = terrain_frag.handle, pName = "main"}}; terrain_bindings := [2]vk.VertexInputBindingDescription{{binding = 0, stride = u32(size_of(Combat_3D_Terrain_Mesh_Vertex)), inputRate = .VERTEX}, {binding = 1, stride = u32(size_of(Combat_3D_Terrain_Instance)), inputRate = .INSTANCE}}; terrain_attributes := [5]vk.VertexInputAttributeDescription{{location = 0, binding = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Combat_3D_Terrain_Mesh_Vertex, local_position))}, {location = 1, binding = 1, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Combat_3D_Terrain_Instance, center))}, {location = 2, binding = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(Combat_3D_Terrain_Instance, shape))}, {location = 3, binding = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(Combat_3D_Terrain_Instance, style))}, {location = 4, binding = 1, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Combat_3D_Terrain_Instance, color))}}; terrain_vertex_input := vertex_input; terrain_vertex_input.vertexBindingDescriptionCount = 2; terrain_vertex_input.pVertexBindingDescriptions = raw_data(terrain_bindings[:]); terrain_vertex_input.vertexAttributeDescriptionCount = 5; terrain_vertex_input.pVertexAttributeDescriptions = raw_data(terrain_attributes[:]); terrain_assembly := assembly; terrain_assembly.topology = .TRIANGLE_LIST; terrain_depth := depth; terrain_depth.depthWriteEnable = true; terrain_raster := raster; terrain_raster.cullMode = {.BACK}; terrain_info := pipeline_info; terrain_info.pStages = raw_data(terrain_stages[:]); terrain_info.pVertexInputState = &terrain_vertex_input; terrain_info.pInputAssemblyState = &terrain_assembly; terrain_info.pDepthStencilState = &terrain_depth; terrain_info.pRasterizationState = &terrain_raster; if !render3d.create_color_pipeline_variants(ctx, &terrain_info, .D32_SFLOAT, &combat_3d.terrain_pipeline) do return false; terrain_survey_depth := terrain_depth; terrain_survey_depth.depthWriteEnable = false; terrain_survey_info := terrain_info; terrain_survey_info.pDepthStencilState = &terrain_survey_depth; if !render3d.create_color_pipeline_variants(ctx, &terrain_survey_info, .D32_SFLOAT, &combat_3d.terrain_survey_pipeline) do return false
	nebula_vert, nebula_frag: engine.Vk_Shader_Module; if !engine.vk_load_shader_module(ctx, "shaders/close_engagement_nebula.vert.spv", &nebula_vert) do return false; defer engine.vk_destroy_shader_module(ctx, &nebula_vert); if !engine.vk_load_shader_module(ctx, "shaders/close_engagement_nebula.frag.spv", &nebula_frag) do return false; defer engine.vk_destroy_shader_module(ctx, &nebula_frag)
	nebula_stages := [2]vk.PipelineShaderStageCreateInfo{{sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.VERTEX}, module = nebula_vert.handle, pName = "main"}, {sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.FRAGMENT}, module = nebula_frag.handle, pName = "main"}}
	nebula_bindings := [2]vk.VertexInputBindingDescription{{binding = 0, stride = u32(size_of(Combat_3D_Terrain_Mesh_Vertex)), inputRate = .VERTEX}, {binding = 1, stride = u32(size_of(Combat_3D_Nebula_Instance)), inputRate = .INSTANCE}}
	nebula_attributes := [5]vk.VertexInputAttributeDescription{{location = 0, binding = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Combat_3D_Terrain_Mesh_Vertex, local_position))}, {location = 1, binding = 1, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Combat_3D_Nebula_Instance, center))}, {location = 2, binding = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(Combat_3D_Nebula_Instance, radii_density))}, {location = 3, binding = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(Combat_3D_Nebula_Instance, style))}, {location = 4, binding = 1, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Combat_3D_Nebula_Instance, color))}}
	nebula_vertex_input := vertex_input; nebula_vertex_input.vertexBindingDescriptionCount = 2; nebula_vertex_input.pVertexBindingDescriptions = raw_data(nebula_bindings[:]); nebula_vertex_input.vertexAttributeDescriptionCount = 5; nebula_vertex_input.pVertexAttributeDescriptions = raw_data(nebula_attributes[:])
	nebula_depth := depth; nebula_depth.depthWriteEnable = false
	nebula_blend_attachment := blend_attachment; nebula_blend_attachment.srcColorBlendFactor = .ONE
	nebula_blend := blend; nebula_blend.pAttachments = &nebula_blend_attachment
	nebula_info := pipeline_info; nebula_info.pStages = raw_data(nebula_stages[:]); nebula_info.pVertexInputState = &nebula_vertex_input; nebula_info.pDepthStencilState = &nebula_depth; nebula_info.pColorBlendState = &nebula_blend
	if !render3d.create_color_pipeline_variants(ctx, &nebula_info, .D32_SFLOAT, &combat_3d.nebula_pipeline) do return false
	// The halo is the same depth-tested geometry sampled at small framebuffer
	// offsets. Additive blending makes those samples emit light; disabling depth
	// writes prevents the halo from occluding the crisp line pass that follows.
	glow_blend_attachment :=
		blend_attachment; glow_blend_attachment.srcColorBlendFactor = .SRC_ALPHA; glow_blend_attachment.dstColorBlendFactor = .ONE; glow_blend_attachment.srcAlphaBlendFactor = .ONE; glow_blend_attachment.dstAlphaBlendFactor = .ONE; glow_blend := blend; glow_blend.pAttachments = &glow_blend_attachment; glow_depth := depth; glow_depth.depthWriteEnable = false; glow_info := pipeline_info; glow_info.pColorBlendState = &glow_blend; glow_info.pDepthStencilState = &glow_depth; if !render3d.create_color_pipeline_variants(ctx, &glow_info, .D32_SFLOAT, &combat_3d.glow_pipeline) do return false
	bg_vert, bg_frag: engine.Vk_Shader_Module; if !engine.vk_load_shader_module(ctx, "shaders/close_engagement_background.vert.spv", &bg_vert) do return false; defer engine.vk_destroy_shader_module(ctx, &bg_vert); if !engine.vk_load_shader_module(ctx, "shaders/close_engagement_background.frag.spv", &bg_frag) do return false; defer engine.vk_destroy_shader_module(ctx, &bg_frag)
	bg_stages := [2]vk.PipelineShaderStageCreateInfo {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = bg_vert.handle,
			pName = "main",
		},
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = bg_frag.handle,
			pName = "main",
		},
	}; bg_assembly := assembly; bg_assembly.topology = .TRIANGLE_LIST; bg_depth := depth; bg_depth.depthTestEnable = false; bg_depth.depthWriteEnable = false; bg_blend := blend_attachment; bg_blend.blendEnable = false; bg_blend_state := blend; bg_blend_state.pAttachments = &bg_blend; bg_vertex_input := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	}; bg_info :=
		pipeline_info; bg_info.pStages = raw_data(bg_stages[:]); bg_info.pVertexInputState = &bg_vertex_input; bg_info.pInputAssemblyState = &bg_assembly; bg_info.pDepthStencilState = &bg_depth; bg_info.pColorBlendState = &bg_blend_state; if !render3d.create_color_pipeline_variants(ctx, &bg_info, .D32_SFLOAT, &combat_3d.background_pipeline) do return false
	combat_3d.ctx = ctx; combat_3d.initialized = true; return true
}

combat_3d_world_pass :: proc(pass: ^rl.World_Pass_Context, user_data: rawptr) {
	cpu_start := time.tick_now(
		
	); defer {combat_3d_last_cpu_ms = time.duration_seconds(time.tick_since(cpu_start)) * 1000}; s := transmute(^Ux_State)user_data; if s == nil do return; dark_view := s.screen == .Passage; if s.screen != .Combat && s.screen != .Operation_Planning && !dark_view do return; if !combat_3d_init(pass.ctx) do return
	pipeline_variant := pass.color_format == .R16G16B16A16_SFLOAT ? 1 : 0
	if dark_view {dark_3d_build_reference(s)} else {combat_3d_build_reference(s)}
	if len(combat_3d.vertices) == 0 do return; world_line_count := len(combat_3d.vertices); frame_index := pass.frame.frame_index; buffer := &combat_3d.vertex[frame_index]; glow_buffer := &combat_3d.glow_vertex[frame_index]; instance_buffer := &combat_3d.instance[frame_index]; terrain_buffer := &combat_3d.terrain_instance[frame_index]; nebula_buffer := &combat_3d.nebula_instance[frame_index]; mem.copy_non_overlapping(buffer.mapped, raw_data(combat_3d.vertices[:]), len(combat_3d.vertices) * size_of(Combat_3D_Line_Instance)); if len(combat_3d.glow_vertices) > 0 do mem.copy_non_overlapping(glow_buffer.mapped, raw_data(combat_3d.glow_vertices[:]), len(combat_3d.glow_vertices) * size_of(Combat_3D_Line_Instance)); if len(combat_3d.instances) > 0 do mem.copy_non_overlapping(instance_buffer.mapped, raw_data(combat_3d.instances[:]), len(combat_3d.instances) * size_of(Combat_3D_Instance)); if len(combat_3d.terrain_instances) > 0 do mem.copy_non_overlapping(terrain_buffer.mapped, raw_data(combat_3d.terrain_instances[:]), len(combat_3d.terrain_instances) * size_of(Combat_3D_Terrain_Instance)); if len(combat_3d.nebula_instances) > 0 do mem.copy_non_overlapping(nebula_buffer.mapped, raw_data(combat_3d.nebula_instances[:]), len(combat_3d.nebula_instances) * size_of(Combat_3D_Nebula_Instance)); if combat_3d.creature_gene_count > 0 do mem.copy_non_overlapping(combat_3d.creature_gene[frame_index].mapped, raw_data(combat_3d.creature_genes[:combat_3d.creature_gene_count]), combat_3d.creature_gene_count * size_of(Combat_3D_Creature_GPU_Gene))
	sx :=
		f32(pass.framebuffer_extent.width) /
		f32(
			max(pass.logical_extent[0], 1),
		); sy := f32(pass.framebuffer_extent.height) / f32(max(pass.logical_extent[1], 1)); view_rect := dark_view ? CONTINUOUS_DARK_VIEW : COMBAT_VIEWPORT; x := (ux_origin.x + view_rect.x * ux_zoom) * sx; y := (ux_origin.y + view_rect.y * ux_zoom) * sy; width := view_rect.width * ux_zoom * sx; height := view_rect.height * ux_zoom * sy
	viewport := vk.Viewport {
		x        = x,
		y        = y,
		width    = width,
		height   = height,
		minDepth = 0,
		maxDepth = 1,
	}; scissor := vk.Rect2D {
		offset = {i32(x), i32(y)},
		extent = {u32(width), u32(height)},
	}; vk.CmdSetViewport(
		pass.frame.command_buffer,
		0,
		1,
		&viewport,
	); vk.CmdSetScissor(pass.frame.command_buffer, 0, 1, &scissor)
	camera := dark_view ? dark_3d_camera_position(s) : combat_3d_camera_position(s)
	dark_light := combat_quat_inverse_rotate(combat_default_orientation(), {120, -95, -650})
	if dark_view {position := s.campaign.passage.dark_navigation.position; origin := s.campaign.outer_dark.continuum.anchor_position; dark_light = {f32(position[0] - origin[0]) * 44, f32(position[1] - origin[1]) * 44, f32(position[2] - origin[2]) * 44}}
	push := Combat_3D_Push {
		view_projection     = dark_view ? dark_3d_view_projection(s, width / max(height, 1)) : combat_3d_view_projection(s, width / max(height, 1)),
		viewport_seed       = {
			width,
			height,
			f32((dark_view ? s.campaign.outer_dark.seed : s.combat.seed) % 16777216),
			dark_view ? f32(s.campaign.outer_dark.continuum.simulation_tick) * f32(game.DARK_FIXED_STEP) : 0,
		},
		camera_position     = {camera.x, camera.y, camera.z, 1},
		dark_light_position = dark_view ? {dark_light.x, dark_light.y, dark_light.z, 1} : {0, 0, 0, 0},
	}
	dark_globals := Dark_Render_Globals{}
	if dark_view {
		d := &s.campaign.outer_dark.continuum; p := &s.campaign.passage; n := &p.dark_navigation
		law, weather := game.dark_environment_at(d, n.position)
		topology := n.forecast.topology_confidence
		if s.dark_course_draft.waypoint_count >= 2 do topology = game.dark_course_forecast(d, &s.dark_course_draft).topology_confidence
		depth := game.dark_depth_from_anchor(d.seed, d.anchor_position, n.position)
		limit := max(game.passage_coherence_limit(p), .001)
		fraction := math.abs(
			depth / DARK_DEPTH_BAND_SPACING - math.round(depth / DARK_DEPTH_BAND_SPACING),
		)
		crossing_pulse := clamp(1 - fraction / .08, 0, 1)
		dark_globals = {
			anchor_band  = {0, 0, 0, f32(DARK_DEPTH_BAND_SPACING * 44)},
			fleet_depth  = {dark_light.x, dark_light.y, dark_light.z, f32(depth)},
			environment  = {
				f32(topology),
				f32(p.coherence_exposure / limit),
				f32(law),
				f32(weather),
			},
			presentation = {
				f32(d.simulation_time + d.accumulator),
				s.reduced_motion ? 1 : 0,
				1,
				f32(crossing_pulse),
			},
		}
	}
	mem.copy_non_overlapping(
		combat_3d.dark_globals[frame_index].mapped,
		&dark_globals,
		size_of(dark_globals),
	)
	vk.CmdPushConstants(
		pass.frame.command_buffer,
		combat_3d.pipeline_layout,
		{.VERTEX, .FRAGMENT},
		0,
		u32(size_of(push)),
		&push,
	)
	vk.CmdBindDescriptorSets(
		pass.frame.command_buffer,
		.GRAPHICS,
		combat_3d.pipeline_layout,
		0,
		1,
		&combat_3d.creature_descriptors[frame_index],
		0,
		nil,
	)
	vk.CmdBindPipeline(
		pass.frame.command_buffer,
		.GRAPHICS,
		combat_3d.background_pipeline[pipeline_variant],
	); vk.CmdDraw(pass.frame.command_buffer, 3, 1, 0, 0)
	if !dark_view && len(combat_3d.nebula_instances) > 0 {
		nebula_buffers := [2]vk.Buffer{combat_3d.terrain_mesh_vertex.handle, nebula_buffer.handle}
		nebula_offsets := [2]vk.DeviceSize{0, 0}
		vk.CmdBindPipeline(pass.frame.command_buffer, .GRAPHICS, combat_3d.nebula_pipeline[pipeline_variant])
		vk.CmdBindVertexBuffers(pass.frame.command_buffer, 0, 2, raw_data(nebula_buffers[:]), raw_data(nebula_offsets[:]))
		vk.CmdBindIndexBuffer(pass.frame.command_buffer, combat_3d.terrain_mesh_index.handle, 0, .UINT32)
		vk.CmdDrawIndexed(pass.frame.command_buffer, combat_3d.terrain_sphere_count, u32(len(combat_3d.nebula_instances)), combat_3d.terrain_sphere_first, 0, 0)
	}
	if false &&
	   len(combat_3d.terrain_instances) >
		   0 {terrain_buffers := [2]vk.Buffer{combat_3d.terrain_mesh_vertex.handle, terrain_buffer.handle}; terrain_offsets := [2]vk.DeviceSize{0, 0}; vk.CmdBindPipeline(pass.frame.command_buffer, .GRAPHICS, combat_3d.terrain_pipeline[pipeline_variant]); vk.CmdBindVertexBuffers(pass.frame.command_buffer, 0, 2, raw_data(terrain_buffers[:]), raw_data(terrain_offsets[:])); vk.CmdBindIndexBuffer(pass.frame.command_buffer, combat_3d.terrain_mesh_index.handle, 0, .UINT32); if combat_3d.terrain_volume_count > 0 do vk.CmdDrawIndexed(pass.frame.command_buffer, combat_3d.terrain_sphere_count, combat_3d.terrain_volume_count, combat_3d.terrain_sphere_first, 0, 0); if combat_3d.terrain_lane_instance_count > 0 do vk.CmdDrawIndexed(pass.frame.command_buffer, combat_3d.terrain_lane_count, combat_3d.terrain_lane_instance_count, combat_3d.terrain_lane_first, 0, combat_3d.terrain_lane_instance_first)}
	if len(combat_3d.instances) >
	   0 {contact_buffers := [2]vk.Buffer{combat_3d.glyph_vertex.handle, instance_buffer.handle}; contact_offsets := [2]vk.DeviceSize{0, 0}; vk.CmdBindPipeline(pass.frame.command_buffer, .GRAPHICS, combat_3d.contact_pipeline[pipeline_variant]); vk.CmdBindVertexBuffers(pass.frame.command_buffer, 0, 2, raw_data(contact_buffers[:]), raw_data(contact_offsets[:])); vk.CmdBindIndexBuffer(pass.frame.command_buffer, combat_3d.glyph_index.handle, 0, .UINT32); for role in 0 ..< 6 do if combat_3d.instance_count[role] > 0 do vk.CmdDrawIndexed(pass.frame.command_buffer, combat_3d.glyph_count[role], combat_3d.instance_count[role], combat_3d.glyph_first[role], 0, combat_3d.instance_first[role])}
	offset := vk.DeviceSize(
		0,
	); line_offsets := [2]vk.DeviceSize{0, 0}; glow_buffers := [2]vk.Buffer{combat_3d.line_vertex.handle, glow_buffer.handle}; vk.CmdBindVertexBuffers(pass.frame.command_buffer, 0, 2, raw_data(glow_buffers[:]), raw_data(line_offsets[:])); vk.CmdBindPipeline(pass.frame.command_buffer, .GRAPHICS, combat_3d.glow_pipeline[pipeline_variant])
	halo_offsets := [12][3]f32 {
		{-3, 0, .022},
		{3, 0, .022},
		{0, -3, .022},
		{0, 3, .022},
		{-2, -2, .03},
		{2, -2, .03},
		{-2, 2, .03},
		{2, 2, .03},
		{-1, 0, .075},
		{1, 0, .075},
		{0, -1, .075},
		{0, 1, .075},
	}
	for halo in halo_offsets {push.glow = {halo[0] * 2 / max(width, 1), halo[1] * 2 / max(height, 1), halo[2], 0}
		vk.CmdPushConstants(
			pass.frame.command_buffer,
			combat_3d.pipeline_layout,
			{.VERTEX, .FRAGMENT},
			0,
			u32(size_of(push)),
			&push,
		)
		vk.CmdDraw(pass.frame.command_buffer, 6, u32(len(combat_3d.glow_vertices)), 0, 0)}
	push.glow =
		{}; vk.CmdPushConstants(pass.frame.command_buffer, combat_3d.pipeline_layout, {.VERTEX, .FRAGMENT}, 0, u32(size_of(push)), &push); line_buffers := [2]vk.Buffer{combat_3d.line_vertex.handle, buffer.handle}; vk.CmdBindVertexBuffers(pass.frame.command_buffer, 0, 2, raw_data(line_buffers[:]), raw_data(line_offsets[:])); vk.CmdBindPipeline(pass.frame.command_buffer, .GRAPHICS, combat_3d.pipeline[pipeline_variant]); vk.CmdDraw(pass.frame.command_buffer, 6, u32(world_line_count), 0, 0)
	// Resolve implicit volumes after world marks have established their actual
	// depth. Ray-hit SV_Depth now decides whether a lobe lies before or behind a
	// ship, wake, shell, or organism instead of the proxy sphere deciding it.
	if len(combat_3d.terrain_instances) > 0 {
		vk.CmdBindDescriptorSets(
			pass.frame.command_buffer,
			.GRAPHICS,
			combat_3d.pipeline_layout,
			0,
			1,
			&combat_3d.creature_descriptors[frame_index],
			0,
			nil,
		)
		terrain_buffers := [2]vk.Buffer {
			combat_3d.terrain_mesh_vertex.handle,
			terrain_buffer.handle,
		}
		terrain_offsets := [2]vk.DeviceSize{0, 0}
		vk.CmdBindPipeline(
			pass.frame.command_buffer,
			.GRAPHICS,
			combat_3d.terrain_pipeline[pipeline_variant],
		)
		vk.CmdBindVertexBuffers(
			pass.frame.command_buffer,
			0,
			2,
			raw_data(terrain_buffers[:]),
			raw_data(terrain_offsets[:]),
		)
		vk.CmdBindIndexBuffer(
			pass.frame.command_buffer,
			combat_3d.terrain_mesh_index.handle,
			0,
			.UINT32,
		)
		if combat_3d.terrain_volume_count > 0 do vk.CmdDrawIndexed(pass.frame.command_buffer, combat_3d.terrain_sphere_count, combat_3d.terrain_volume_count, combat_3d.terrain_sphere_first, 0, 0)
		if combat_3d.terrain_lane_instance_count > 0 do vk.CmdDrawIndexed(pass.frame.command_buffer, combat_3d.terrain_lane_count, combat_3d.terrain_lane_instance_count, combat_3d.terrain_lane_first, 0, combat_3d.terrain_lane_instance_first)
		if dark_view && combat_3d.terrain_survey_instance_count > 0 {
			vk.CmdBindPipeline(
				pass.frame.command_buffer,
				.GRAPHICS,
				combat_3d.terrain_survey_pipeline[pipeline_variant],
			)
			vk.CmdDrawIndexed(
				pass.frame.command_buffer,
				combat_3d.terrain_sphere_count,
				combat_3d.terrain_survey_instance_count,
				combat_3d.terrain_sphere_first,
				0,
				combat_3d.terrain_survey_instance_first,
			)
		}
	}
}

combat_3d_shutdown :: proc() {if !combat_3d.initialized do return; ctx := combat_3d.ctx; _ =
		vk.DeviceWaitIdle(ctx.device)
	render3d.destroy_color_pipeline_variants(ctx, &combat_3d.pipeline)
	render3d.destroy_color_pipeline_variants(ctx, &combat_3d.contact_pipeline)
	render3d.destroy_color_pipeline_variants(ctx, &combat_3d.terrain_pipeline)
	render3d.destroy_color_pipeline_variants(ctx, &combat_3d.terrain_survey_pipeline)
	render3d.destroy_color_pipeline_variants(ctx, &combat_3d.glow_pipeline)
	render3d.destroy_color_pipeline_variants(ctx, &combat_3d.background_pipeline)
	render3d.destroy_color_pipeline_variants(ctx, &combat_3d.nebula_pipeline)
	if combat_3d.pipeline_layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(ctx.device, combat_3d.pipeline_layout, nil)
	if combat_3d.creature_descriptor_pool != vk.DescriptorPool(0) do vk.DestroyDescriptorPool(ctx.device, combat_3d.creature_descriptor_pool, nil)
	if combat_3d.creature_descriptor_layout != vk.DescriptorSetLayout(0) do vk.DestroyDescriptorSetLayout(ctx.device, combat_3d.creature_descriptor_layout, nil)
	engine.vk_destroy_buffer(ctx, &combat_3d.line_vertex)
	engine.vk_destroy_buffer(ctx, &combat_3d.glyph_vertex)
	engine.vk_destroy_buffer(ctx, &combat_3d.glyph_index)
	engine.vk_destroy_buffer(ctx, &combat_3d.terrain_mesh_vertex)
	engine.vk_destroy_buffer(ctx, &combat_3d.terrain_mesh_index)
	for i := 0; i < engine.MAX_FRAMES_IN_FLIGHT; i += 1 {
		engine.vk_destroy_buffer(ctx, &combat_3d.vertex[i])
		engine.vk_destroy_buffer(ctx, &combat_3d.glow_vertex[i])
		engine.vk_destroy_buffer(ctx, &combat_3d.instance[i])
		engine.vk_destroy_buffer(ctx, &combat_3d.terrain_instance[i])
		engine.vk_destroy_buffer(ctx, &combat_3d.nebula_instance[i])}
	for i := 0; i < engine.MAX_FRAMES_IN_FLIGHT; i += 1 {
		engine.vk_destroy_buffer(ctx, &combat_3d.creature_gene[i])
		engine.vk_destroy_buffer(ctx, &combat_3d.dark_globals[i])
	}
	delete(combat_3d.vertices)
	delete(combat_3d.glow_vertices)
	delete(combat_3d.instances)
	delete(combat_3d.terrain_instances)
	delete(combat_3d.nebula_instances)
	combat_3d = {}}
