const std = @import("std");

/// Converts a Field ID to a virtual table offset.
pub inline fn fieldIndexToOffset(field_id: u16) u16 {
    // Should correspond to what EndTable() below builds up.
    return (field_id + 2) * @sizeOf(u16);
}

pub const Builder = struct {

    //    protected:
    //  // You shouldn't really be copying instances of this class.
    //  FlatBufferBuilder(const FlatBufferBuilder &);
    //  FlatBufferBuilder &operator=(const FlatBufferBuilder &);

    //  void Finish(uoffset_t root, const char *file_identifier, bool size_prefix) {
    //    NotNested();
    //    buf_.clear_scratch();
    //    // This will cause the whole buffer to be aligned.
    //    PreAlign((size_prefix ? sizeof(uoffset_t) : 0) + sizeof(uoffset_t) +
    //                 (file_identifier ? kFileIdentifierLength : 0),
    //             minalign_);
    //    if (file_identifier) {
    //      FLATBUFFERS_ASSERT(strlen(file_identifier) == kFileIdentifierLength);
    //      PushBytes(reinterpret_cast<const uint8_t *>(file_identifier),
    //                kFileIdentifierLength);
    //    }
    //    PushElement(ReferTo(root));  // Location of root.
    //    if (size_prefix) { PushElement(GetSize()); }
    //    finished = true;
    //  }

    //     explicit FlatBufferBuilder(
    //     size_t initial_size = 1024, Allocator *allocator = nullptr,
    //     bool own_allocator = false,
    //     size_t buffer_minalign = AlignOf<largest_scalar_t>())
    //     : buf_(initial_size, allocator, own_allocator, buffer_minalign),
    //       num_field_loc(0),
    //       max_voffset_(0),
    //       nested(false),
    //       finished(false),
    //       minalign_(1),
    //       force_defaults_(false),
    //       dedup_vtables_(true),
    //       string_pool(nullptr) {
    //   EndianCheck();
    // }

    buf_: std.ArrayListUnmanaged(u8) = .{},
    //  // Accumulating offsets of table members while it is being built.
    //  // We store these in the scratch pad of buf_, after the vtable offsets.
    num_field_loc: u32 = 0,
    //  // Track how much of the vtable is in use, so we can output the most compact
    //  // possible vtable.
    max_voffset_: u16 = 0,
    //  // Ensure objects are not nested.
    nested: bool = false,
    //  // Ensure the buffer is finished before it is being accessed.
    finished: bool = false,
    minalign_: usize = 1,
    force_defaults_: bool = false, // Serialize values equal to their defaults anyway.
    dedup_vtables_: bool = false,

    //  struct StringOffsetCompare {
    //    StringOffsetCompare(const vector_downward &buf) : buf_(&buf) {}
    //    operator: bool = false ,)(const Offset<String> &a, const Offset<String> &b) const {
    //      auto stra = reinterpret_cast<const String *>(buf_->data_at(a.o));
    //      auto strb = reinterpret_cast<const String *>(buf_->data_at(b.o));
    //      return StringLessThan(stra->data(), stra->size(), strb->data(),
    //                            strb->size());
    //    }
    //    const vector_downward *buf_;
    //  };

    //  // For use with CreateSharedString. Instantiated on first use only.
    //  typedef std::set<Offset<String>, StringOffsetCompare> StringOffsetMap;

    string_pool: StringOffsetMap = .{},

    // private:
    //  // Allocates space for a vector of structures.
    //  // Must be completed with EndVectorOfStructs().
    //  template<typename T> T *StartVectorOfStructs(size_t vector_size) {
    //    StartVector(vector_size * sizeof(T) / AlignOf<T>(), sizeof(T), AlignOf<T>());
    //    return reinterpret_cast<T *>(buf_.make_space(vector_size * sizeof(T)));
    //  }

    //  // End the vector of structures in the flatbuffers.
    //  // Vector should have previously be started with StartVectorOfStructs().
    //  template<typename T>
    //  Offset<Vector<const T *>> EndVectorOfStructs(size_t vector_size) {
    //    return Offset<Vector<const T *>>(EndVector(vector_size));
    //  }
    pub const StringOffsetMap = std.AutoHashMapUnmanaged(void, void);
    pub const FieldLoc = struct {
        off: u32,
        id: u16,
    };

    pub fn clearOffsets(b: *Builder) void {
        // b.buf_.scratch_pop(b.num_field_loc * @sizeOf(FieldLoc));
        b.num_field_loc = 0;
        b.max_voffset_ = 0;
    }

    pub fn clear(b: *Builder) void {
        b.clearOffsets();
        b.buf_.clearRetainingCapacity();
        b.nested = false;
        b.finished = false;
        b.minalign_ = 1;
        b.string_pool.clearRetainingCapacity();
    }
};
