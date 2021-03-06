module MiniLogging

export get_logger, basic_config
export @debug, @info, @warn, @error, @critical

include("Hierarchy.jl")
using .Hierarchy

@enum LogLevel NOTSET DEBUG INFO WARN ERROR CRITICAL

type Handler
    output::IO
    date_format::String
end

type Logger
    name::String
    level::LogLevel
    handlers::Vector{Handler}
end

function Base.show(io::IO, logger::MiniLogging.Logger)
    if (is_root(logger.name))
        print(io, "RootLogger($(logger.level))")
    else
        print(io,
            """Logger("$(logger.name)", $(logger.level))"""
        )
    end
end

Logger(name::String, level::LogLevel) = Logger(name, level, Handler[])

const TREE = Tree()
const ROOT = Logger("", WARN)
const LOGGERS = Dict{String, Logger}("" => ROOT)

is_root(name::String) = name == "" || name == "Main"

get_logger() = ROOT

"""
- `@assert get_logger("") == get_logger() == get_logger("Main")`
"""
function get_logger(name::String)::Logger
    if is_root(name)
        return get_logger()
    end

    if haskey(LOGGERS, name)
        return LOGGERS[name]
    end

    push!(TREE, name)
    logger = Logger(name, NOTSET)
    LOGGERS[name] = logger
    logger
end

get_logger(name) = get_logger(string(name))

is_not_set(logger::Logger) = logger.level == NOTSET

function get_effective_level(logger::Logger)::LogLevel
    logger_name = logger.name
    while !is_root(logger_name)
        if !is_not_set(logger)
            return logger.level
        end
        logger_name = parent_node(TREE, logger.name)
        logger = LOGGERS[logger_name]
    end
    # This is `ROOT`.
    return logger.level
end

is_enabled_for(logger::Logger, level::LogLevel) = level >= get_effective_level(logger)

has_handlers(logger::Logger) = !isempty(logger.handlers)

function get_effective_handlers(logger::Logger)::Vector{Handler}
    logger_name = logger.name
    while !is_root(logger_name)
        if has_handlers(logger)
            return logger.handlers
        end
        logger_name = parent_node(TREE, logger.name)
        logger = LOGGERS[logger_name]
    end
    # This is `ROOT`.
    return logger.handlers
end


function basic_config(level::LogLevel; date_format::String="%Y-%m-%d %H:%M:%S")
    ROOT.level = level
    handler = Handler(STDERR, date_format)
    push!(ROOT.handlers, handler)
end

write_log{T<:IO}(output::T, color::Symbol, msg::AbstractString) = (print(output, msg); flush(output))
write_log(output::Base.TTY, color::Symbol, msg::AbstractString) = Base.print_with_color(color, output, msg)

function _log(
        logger::Logger, level::LogLevel, color::Symbol,
        msg...
    )
    logger_name = is_root(logger.name) ? "Main" : logger.name
    for handler in get_effective_handlers(logger)
        t = Libc.strftime(handler.date_format, time())
        s = string(t, ":" , level, ":", logger_name, ":" , msg..., "\n")
        write_log(handler.output, color, s)
    end
end


for (fn, level, color) in [
        (:debug,    DEBUG,    :cyan),
        (:info,     INFO,     :blue),
        (:warn,     WARN,  :magenta),
        (:error,      ERROR,    :red),
        (:critical, CRITICAL, :red)
    ]

    @eval macro $fn(logger, msg...)
        level = $level
        # This generates e.g. `:red`.
        color = $(Expr(:quote, color))
        msg = map(esc, msg)
        quote
            logger = $(esc(logger))
            if is_enabled_for(logger, $level)
                _log(logger, $level, $(Expr(:quote, color)), $(msg...))
            end
        end
    end
end



end