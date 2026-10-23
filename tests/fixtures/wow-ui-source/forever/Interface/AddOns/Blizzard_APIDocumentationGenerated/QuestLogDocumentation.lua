local QuestLog =
{
	Name = "QuestLog",
	Type = "System",
	Namespace = "C_QuestLog",
	Environment = "All",

	Functions =
	{
		{
			Name = "GetInfo",
			Type = "Function",
			Documentation = { "Returns info for a quest log entry." },

			Arguments =
			{
				{ Name = "questLogIndex", Type = "number", Nilable = false },
			},

			Returns =
			{
				{ Name = "info", Type = "QuestInfo", Nilable = true },
			},
		},
		{
			Name = "GetQuestTagInfo",
			Type = "Function",

			Arguments =
			{
				{ Name = "questID", Type = "number", Nilable = false },
			},

			Returns =
			{
				{ Name = "tagInfo", Type = "table", InnerType = "QuestTagInfo", Nilable = true },
			},
		},
	},

	Events =
	{
		{
			Name = "QuestAccepted",
			Type = "Event",
			LiteralName = "QUEST_ACCEPTED",
			SynchronousEvent = true,
			Payload =
			{
				{ Name = "questID", Type = "number", Nilable = false },
			},
		},
	},

	Tables =
	{
		{
			Name = "QuestTagType",
			Type = "Enumeration",
			NumValues = 2,
			MinValue = 0,
			MaxValue = 1,
			Fields =
			{
				{ Name = "Tag", Type = "QuestTagType", EnumValue = 0 },
				{ Name = "Profession", Type = "QuestTagType", EnumValue = 1 },
			},
		},
	},
};

APIDocumentation:AddDocumentationTable(QuestLog);
