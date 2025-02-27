"""
RosBag.jl

this package reproduces the "rosbag command-line tool" for Julia
record
Record a bag file with the contents of specified topics.

info IMPLEMENTED 
Summarize the contents of a bag file.

play (not implemented)
Play back the contents of one or more bag files.

check (not implemented)
Determine whether a bag is playable in the current system, or if it can be migrated.

fix (not implemented)
Repair the messages in a bag file so that it can be played in the current system.

filter (not implemented)
Convert a bag file using Python expressions.

compress (not implemented)
Compress one or more bag files.

decompress (not implemented)
Decompress one or more bag files.

reindex (not implemented)
Reindex one or more broken bag files.


"""


using Revise
using Dates


struct Field

    len::UInt32
    name::String
    value::Vector{UInt8}
end

struct Record

    header_len::UInt32
    header::Dict{String,Field}
    data_len::UInt32
    data::Vector{UInt8}

end

struct Msgtype

    type::String
    md5sum::Vector{UInt8}
end

mutable struct Topic

    name::String
    type::Msgtype
    n_msg::Int32
    frec::Float32
    conns::Vector{UInt32}

end

"""
struct con metadata del BagFile
es posible que se agregue el IO y un puntero de referncia?

"""

mutable struct BagFile

    path::String
    version::String
    duration::Millisecond
    start_time::DateTime
    end_time::DateTime
    size::Int64
    messages::Int64
    compression::String
    chunks::UInt32
    types::Dict{String,Msgtype}
    topics::Dict{String,Topic}
    connections::Dict{UInt32,String}

end

function BagFile(path; version="#ROSBAG V2.0", duration=Millisecond(0), start_time=unix2datetime(typemax(Int32)), end_time=unix2datetime(0), size=0, messages=0, compression="none", chunks=0, types=Dict{String,Msgtype}(), topics=Dict{String,Topic}(), connections=Dict{UInt32,String}())

    return BagFile(path, version, duration, start_time, end_time, size, messages, compression, chunks, types, topics, connections)

end

function Base.show(io::IO, ::MIME"text/plain", bag::BagFile)
    print(io, "path:\t\t $(bag.path) \n")
    print(io, "version:\t $(bag.version) \n")
    print(io, "duration:\t $(floor(bag.duration, Dates.Minute)):$(floor(mod(bag.duration, Millisecond(60000)), Dates.Second)) ($(floor(bag.duration, Dates.Second)))\n")
    print(io, "start:\t\t $(bag.start_time) \n")
    print(io, "end:\t\t $(bag.end_time) \n")
    if bag.size < 1024^2
        print(io, "size:\t\t $(bag.size/1024)kB \n")
    elseif bag.size < 1024^3
        print(io, "size:\t\t $(bag.size/1024/1024)MB \n")
    elseif bag.size < 1024^4
        print(io, "size:\t\t $(bag.size/1024/1024/1024)GB \n")
    end
    print(io, "messages:\t $(bag.messages) \n")
    print(io, "compression:\t $(bag.compression) [$(bag.chunks)/$(bag.chunks) chunks]\n")
    print(io, "types:")
    for key in sort(collect(keys(bag.types)))
        print(io, "\t\t $key \t\t [$(String(copy(bag.types[key].md5sum)))]\n")
    end
    print(io, "types:")
    for key in sort(collect(keys(bag.topics)))
        print(io, "\t\t $key \t\t $(bag.topics[key].n_msg) msgs\t : $(bag.topics[key].type.type)\n")
    end
end

#=
function Base.show(io::IO, bag::BagFile)
    print(io, "path:\t $bag.path \n")
    print(io, "version:\t $bag.version \n")

end
=#
"""
Funcion para leer la primera linea del rosbag y verificar que esta OK

"""

function leer_bag_header(io::IO)

    h = readline(io)
    println(h)
    expected = "#ROSBAG V2.0"
    if h == expected
        return true
    else
        return false
    end
end

"""
funcion que lee un record, avanza el io hasta el final del record y devuelve un struct del tipo Record

"""

function leer_record(io::IO)

    header_len = read(io, UInt32)
    #println("el lenght del header es $header_len")
    header_hex = Vector{UInt8}(undef, header_len)
    readbytes!(io, header_hex)
    #ahora tengo que leer los fields
    header = Dict{String,Field}()
    counter = 1
    while counter < header_len
        field_len = copy(reinterpret(UInt32, header_hex[counter:(counter+3)]))[1]
        #println("length de field = $field_len")
        counter = counter + 4
        field_name_value = header_hex[counter:(counter+field_len-1)]
        counter = counter + field_len
        separator = findfirst(==(0x3d), field_name_value)
        field_name = String(field_name_value[1:(separator-1)])
        field_value = field_name_value[(separator+1):end]
        field = Field(field_len, field_name, field_value)
        header[field_name] = field
        #println("Field = $field")
    end

    data_len = read(io, UInt32)
    #println("el lenght del data es $data_len")
    data_hex = Vector{UInt8}(undef, data_len)
    readbytes!(io, data_hex)

    return Record(header_len, header, data_len, data_hex)

end



"""
Funcion que recibe un bag y devuelve lista (o dict) con los topics
"""

function topics(bag::IO)

    topics = Dict{String,Topic}() #dictionary tu return
    leer_bag_header(bag)
    record = leer_record(bag)
    while record.header["op"].value != UInt8[0x07]  #busco topic indormation
        record = leer_record(bag)
    end


    while record.header["op"].value == UInt8[0x07]  #proceso connections 
        if !haskey(topics, String(copy(record.header["topic"].value)))
            topics[String(copy(record.header["topic"].value))] = Topic(String(copy(record.header["topic"].value)), Msgtype("", []), 0, 0.0, copy(reinterpret(UInt32, record.header["conn"].value)))
        end
        #println(String(copy(record.header["topic"].value)))
        record = leer_record(bag)

    end

    return topics


end

"""
function that receives a connection record and returns a Dict with the data
"""
function parse_connection(record::Record)

    if !(record.header["op"].value == UInt8[0x07])
        error("Record is not a Connection")
    else
        data = Dict{String,Field}()
        counter = 1
        while counter < record.data_len
            field_len = copy(reinterpret(UInt32, record.data[counter:(counter+3)]))[1]
            #println("length de field = $field_len")
            counter = counter + 4
            field_name_value = record.data[counter:(counter+field_len-1)]
            counter = counter + field_len
            separator = findfirst(==(0x3d), field_name_value)
            field_name = String(field_name_value[1:(separator-1)])
            field_value = field_name_value[(separator+1):end]
            field = Field(field_len, field_name, field_value)
            data[field_name] = field
            #println("Field = $field")


        end
        return data
    end

end


"""
function that receives a chunk info record and returns a Dict with the data
"""
function parse_chunk_info(record::Record)

    if !(record.header["op"].value == UInt8[0x06])
        error("Record is not a ChunkInfo")
    else
        #count = copy(reinterpret(Int32, record.header["count"].value))
        data = Dict{UInt32,UInt32}()
        counter = 1
        while counter < record.data_len
            data[copy(reinterpret(UInt32, record.data[counter:(counter+3)]))[1]] = copy(reinterpret(UInt32, record.data[(counter+4):(counter+7)]))[1]
            counter = counter + 8

        end
        return data
    end

end


"""
Funcion que inicialize un BagFile y devuelve el struct BagFile con la metadata
"""

function OpenBag(path::String)
    file = open(path)  #abro archivo
    bag = BagFile(path)   #creo BagFile
    bag.size = filesize(path) #tamaño del archivo
    topics = Dict{String,Topic}() #dictionary tu return
    types = Dict{String,Msgtype}() #dictionary tu return
    connections = Dict{UInt32,String}()

    if leer_bag_header(file) #leo primera linea y verifico version 2.0 (unica version comptabible)
        bag.version = "2.0"
    else
        error("BagFile before 2.0 not compatible")
    end

    record = leer_record(file) #lee el primer record que deberia se un bad header 0x03

    bag.chunks = copy(reinterpret(UInt32, record.header["chunk_count"].value))[1] + 0

    record = leer_record(file)

    bag.compression = String(copy(record.header["compression"].value))

    while record.header["op"].value != UInt8[0x07]  #busco topic information
        record = leer_record(file)
    end

    while record.header["op"].value == UInt8[0x07]  #proceso connections y cargo topics
        data = parse_connection(record)

        type = Msgtype(String(copy(data["type"].value)), copy(data["md5sum"].value))

        connections[copy(reinterpret(UInt32, record.header["conn"].value))[1]] = String(copy(record.header["topic"].value))

        if !haskey(topics, String(copy(record.header["topic"].value))) #agrego topic nuevo
            topics[String(copy(record.header["topic"].value))] = Topic(String(copy(record.header["topic"].value)), type, 0, 0.0, copy(reinterpret(UInt32, record.header["conn"].value)))
        else #o solo le agrego info de connection
            append!(topics[String(copy(record.header["topic"].value))].conns, copy(reinterpret(UInt32, record.header["conn"].value)))
        end

        if !haskey(types, String(copy(data["type"].value))) #agrego type nuevo
            types[String(copy(data["type"].value))] = type
        end


        record = leer_record(file)

    end
    bag.topics = topics
    bag.types = types
    bag.connections = connections

    chunk_count = 1
    start_time = bag.start_time
    end_time = bag.end_time

    while record.header["op"].value == UInt8[0x06] #record con informacion de chunks
        chunk_count += 1
        #println(record.header["start_time"].value)
        if unix2datetime(copy(reinterpret(Int32, record.header["start_time"].value))[1] + copy(reinterpret(Int32, record.header["start_time"].value))[2] / 1000 / 1000 / 1000) < start_time
            start_time = unix2datetime(copy(reinterpret(Int32, record.header["start_time"].value))[1] + copy(reinterpret(Int32, record.header["start_time"].value))[2] / 1000 / 1000 / 1000)
        end

        if unix2datetime(copy(reinterpret(Int32, record.header["end_time"].value))[1] + copy(reinterpret(Int32, record.header["end_time"].value))[2] / 1000 / 1000 / 1000) > end_time
            end_time = unix2datetime(copy(reinterpret(Int32, record.header["end_time"].value))[1] + copy(reinterpret(Int32, record.header["end_time"].value))[2] / 1000 / 1000 / 1000)
        end

        count = copy(reinterpret(Int32, record.header["count"].value))
        #println(count)
        #println(record.data)

        data = parse_chunk_info(record)

        for (key, value) in data
            bag.topics[bag.connections[key]].n_msg += value
            bag.messages += value
        end

        if !eof(file)
            record = leer_record(file)
        else
            break
        end

    end

    bag.start_time = start_time
    bag.end_time = end_time
    bag.duration = end_time - start_time

    #print(chunk_count)


    close(file) #cierro al salir
    return bag
end




######### tests #######

# find the BagFile
Bagpath = joinpath(ENV["HOME"], "Facultad/Big_files/Bag_Files/inia_bajo_2022-07-06-12-44-02.bag")

bag_info = OpenBag(Bagpath)

bag_info.start_time
bag_info.end_time
bag_info.end_time - bag_info.start_time
bag_info.size
bag_info.messages
bag_info.topics["/velodyne_points"].n_msg

print(bag_info)
bag_info
bag = open(Bagpath)
close(bag)



topicos = topics(bag)




f = leer_header(bag)
record = leer_record(bag)

record
String(record.header["compression"].value)
record.header["op"].value


while record.header["op"].value == UInt8[0x04] || record.header["op"].value == UInt8[0x05]
    record = leer_record(bag)
end

while record.header["op"].value == UInt8[0x06]
    record = leer_record(bag)
end

a = [3,]

copy(reinterpret(UInt32, record.header["conn"].value))
unix2datetime(88484848)
typeof(filesize(Bagpath))

String(copy(bag_info.types["sensor_msgs/CameraInfo"].md5sum))
bag_info.topics["/rosout"].conns
a = copy(reinterpret(UInt32, bag_info.chunks))
bag_info.compression
unix2datetime((copy(reinterpret(Int32, UInt8[0x7c, 0xb3, 0xc5, 0x62, 0x79, 0x3c, 0xb2, 0x26]))[1]) + (copy(reinterpret(Int32, UInt8[0x7c, 0xb3, 0xc5, 0x62, 0x79, 0x3c, 0xb2, 0x26]))[1]) / 1000 / 1000 / 1000)
a = (copy(reinterpret(Int32, UInt8[0x7c, 0xb3, 0xc5, 0x62, 0x79, 0x3c, 0xb2, 0x26]))[2]) / 1000 / 1000
a = floor(Millisecond(2400000), Dates.Second)
floor(mod(Millisecond(2423120), Millisecond(60000)), Dates.Second)