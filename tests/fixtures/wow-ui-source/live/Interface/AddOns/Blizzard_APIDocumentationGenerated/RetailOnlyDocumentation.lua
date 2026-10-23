local RetailOnly =
{
	Name = "RetailOnly",
	Type = "System",
	Namespace = "C_Soulbinds",
	Environment = "All",

	Functions =
	{
		{
			Name = "GetActiveSoulbindID",
			Type = "Function",

			Returns =
			{
				{ Name = "soulbindID", Type = "number", Nilable = false },
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

APIDocumentation:AddDocumentationTable(RetailOnly);
