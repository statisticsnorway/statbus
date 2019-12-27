namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Class entity user region
    /// </summary>
    public class UserRegion
    {
        public string UserId { get; set; }
        public virtual User User { get; set; }
        public int RegionId { get; set; }
        public virtual Region Region { get; set; }
    }
}
