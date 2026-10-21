local InstanceSerializer = require(script.Parent.InstanceSerializer)
local Safety = require(script.Parent.Safety)

local ModelExporter = {}

function ModelExporter.export(args)
	Safety.assertGeneratedPath(args.rootPath)
	local root = InstanceSerializer.resolve(args.rootPath)
	assert(root, "Export root not found")
	local count = #root:GetDescendants() + 1
	assert(count <= 10000, "Export exceeds 10000 instances")
	local data = game:GetService("SerializationService"):SerializeInstancesAsync({ root })
	assert(buffer.len(data) <= 8 * 1024 * 1024, "Export exceeds 8 MiB")
	local encoded = game:GetService("EncodingService"):Base64Encode(data)
	return {
		rootPath = InstanceSerializer.pathOf(root),
		instanceCount = count,
		byteLength = buffer.len(data),
		data = buffer.tostring(encoded),
	}
end

return ModelExporter
