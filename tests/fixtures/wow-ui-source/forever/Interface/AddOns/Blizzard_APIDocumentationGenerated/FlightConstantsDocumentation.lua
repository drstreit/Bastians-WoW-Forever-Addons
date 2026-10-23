local FlightConstants =
{
	Name = "FlightConstants",
	Type = "System",
	Environment = "All",

	Functions =
	{
	},

	Events =
	{
	},

	Tables =
	{
		{
			Name = "FlightConstants",
			Type = "Constants",
			Values =
			{
				{ Name = "DEFAULT_FACTION", Type = "FlightPathFaction", Value = Enum.FlightPathFaction.Neutral },
				{ Name = "MAX_NODES", Type = "number", Value = Constants.FlightConstants.BASE + 1 },
			},
		},
	},
};

APIDocumentation:AddDocumentationTable(FlightConstants);
