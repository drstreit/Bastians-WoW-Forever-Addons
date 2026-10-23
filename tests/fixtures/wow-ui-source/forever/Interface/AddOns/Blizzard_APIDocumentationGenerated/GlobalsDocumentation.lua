local Globals =
{
	Name = "Globals",
	Type = "System",
	Environment = "All",

	Functions =
	{
		{
			Name = "GetServerTime",
			Type = "Function",

			Returns =
			{
				{ Name = "serverTime", Type = "time_t", Nilable = false },
			},
		},
	},

	Events =
	{
	},

	Tables =
	{
	},
};

APIDocumentation:AddDocumentationTable(Globals);
