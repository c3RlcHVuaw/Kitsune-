using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Kitsune.Core;

/// Config JSON helpers: object keys are written sorted, slashes unescaped (same output rules as the macOS app).
public static class Json
{
    public static string Write(object? value, bool indented)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = indented, Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping }))
            WriteValue(writer, value);
        return Encoding.UTF8.GetString(stream.ToArray());
    }

    static void WriteValue(Utf8JsonWriter w, object? value)
    {
        switch (value)
        {
            case null: w.WriteNullValue(); break;
            case string s: w.WriteStringValue(s); break;
            case bool b: w.WriteBooleanValue(b); break;
            case int i: w.WriteNumberValue(i); break;
            case long l: w.WriteNumberValue(l); break;
            case double d: w.WriteNumberValue(d); break;
            case JsonNode node: WriteValue(w, FromNode(node)); break;
            case IDictionary<string, object?> dict:
                w.WriteStartObject();
                foreach (var key in dict.Keys.OrderBy(k => k, StringComparer.Ordinal)) { w.WritePropertyName(key); WriteValue(w, dict[key]); }
                w.WriteEndObject();
                break;
            case System.Collections.IEnumerable list:
                w.WriteStartArray();
                foreach (var item in list) WriteValue(w, item);
                w.WriteEndArray();
                break;
            default: throw new InvalidOperationException($"Unsupported JSON value {value.GetType()}");
        }
    }

    /// JsonNode tree → plain dictionaries, lists and primitives.
    public static object? FromNode(JsonNode? node) => node switch
    {
        null => null,
        JsonObject o => o.ToDictionary(p => p.Key, p => FromNode(p.Value), StringComparer.Ordinal),
        JsonArray a => a.Select(FromNode).ToList(),
        JsonValue v => FromElement(v.GetValue<JsonElement>()),
        _ => null,
    };

    static object? FromElement(JsonElement e) => e.ValueKind switch
    {
        JsonValueKind.String => e.GetString(),
        JsonValueKind.True => true,
        JsonValueKind.False => false,
        JsonValueKind.Number => e.TryGetInt64(out var l) ? (l is >= int.MinValue and <= int.MaxValue ? (int)l : l) : e.GetDouble(),
        _ => null,
    };

    public static Dictionary<string, object?>? ParseObject(string text)
    {
        try { return FromNode(JsonNode.Parse(text)) as Dictionary<string, object?>; }
        catch (JsonException) { return null; }
    }
}
