using System;
using System.Reflection;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;

namespace nscreg.Data;

public static class DateTimeOffsetExtensions
{
    private const string IsUtcAnnotation = "IsUtc";
    private static readonly ValueConverter<DateTimeOffset, DateTimeOffset> UtcConverter =
        new(convertTo => convertTo.ToUniversalTime(), convertFrom => convertFrom);

    public static PropertyBuilder<TProperty> IsUtc<TProperty>(this PropertyBuilder<TProperty> builder, bool isUtc = true) => builder.HasAnnotation(IsUtcAnnotation, isUtc);

    public static bool IsUtc(this IMutableProperty property)
    {
        if (property != null && property.PropertyInfo != null)
        {
            var attribute = property.PropertyInfo.GetCustomAttribute<IsUtcAttribute>();
            if (attribute is not null && attribute.IsUtc)
            {
                return true;
            }

            return ((bool?)property.FindAnnotation(IsUtcAnnotation)?.Value) ?? true;
        }
        return true;
    }

    /// <summary>
    /// Make sure this is called after configuring all your entities.
    /// </summary>
    public static void ApplyUtcDateTimeOffsetConverter(this ModelBuilder builder)
    {
        foreach (var entityType in builder.Model.GetEntityTypes())
        {
            foreach (var property in entityType.GetProperties())
            {
                if (!property.IsUtc())
                {
                    continue;
                }

                if (property.ClrType == typeof(DateTimeOffset) ||
                    property.ClrType == typeof(DateTimeOffset?))
                {
                    property.SetValueConverter(UtcConverter);
                }
            }
        }
    }
}
public class IsUtcAttribute : Attribute
{
    public IsUtcAttribute(bool isUtc = true) => this.IsUtc = isUtc;
    public bool IsUtc { get; }
}
