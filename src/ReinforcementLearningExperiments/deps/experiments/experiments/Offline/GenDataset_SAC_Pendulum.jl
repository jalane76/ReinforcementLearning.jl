# ---
# title: GenDataset\_SAC\_Pendulum
# description: Collect Pendulum dataset generated by SAC
# date: 2021-09-17
# author: "[Guoyu Yang](https://github.com/pilgrimygy)"
# ---

#+ tangle=true
using ReinforcementLearningCore, ReinforcementLearningBase, ReinforcementLearningZoo
using StableRNGs
using Flux
using Flux.Losses

function RLCore.Experiment(
    ::Val{:GenDataset},
    ::Val{:SAC},
    ::Val{:Pendulum},
    type::AbstractString;
    dataset_size = 10000,
    seed = 123,
)
    rng = StableRNG(seed)
    inner_env = PendulumEnv(T = Float32, rng = rng)
    action_dims = inner_env.n_actions
    A = action_space(inner_env)
    low = A.left
    high = A.right
    ns = length(state(inner_env))
    na = 1

    env = ActionTransformedEnv(
        inner_env;
        action_mapping = x -> low + (x[1] + 1) * 0.5 * (high - low),
    )
    init = glorot_uniform(rng)

    create_policy_net() = NeuralNetworkApproximator(
        model = GaussianNetwork(
            pre = Chain(
                Dense(ns, 30, relu), 
                Dense(30, 30, relu),
            ),
            μ = Chain(Dense(30, na, init = init)),
            logσ = Chain(Dense(30, na, x -> clamp.(x, typeof(x)(-10), typeof(x)(2)), init = init)),
        ),
        optimizer = Adam(0.003),
    )

    create_q_net() = NeuralNetworkApproximator(
        model = Chain(
            Dense(ns + na, 30, relu; init = init),
            Dense(30, 30, relu; init = init),
            Dense(30, 1; init = init),
        ),
        optimizer = Adam(0.003),
    )

    if type == "random"
        start_steps = dataset_size
        trajectory_num = dataset_size
    elseif type == "medium"
        start_steps = 1000
        trajectory_num = dataset_size
    elseif type == "expert"
        start_steps = 1000
        trajectory_num = 10000 + dataset_size
    else
        @error("wrong parameter")
    end 

    agent = Agent(
        policy = SACPolicy(
            policy = create_policy_net(),
            qnetwork1 = create_q_net(),
            qnetwork2 = create_q_net(),
            target_qnetwork1 = create_q_net(),
            target_qnetwork2 = create_q_net(),
            γ = 0.99f0,
            τ = 0.005f0,
            α = 0.2f0,
            batch_size = 64,
            start_steps = start_steps,
            start_policy = RandomPolicy(Space([-1.0..1.0 for _ in 1:na]); rng = rng),
            update_after = 1000,
            update_freq = 1,
            automatic_entropy_tuning = true,
            lr_alpha = 0.003f0,
            action_dims = action_dims,
            rng = rng,
        ),
        trajectory = CircularArraySARTTrajectory(
            capacity = dataset_size+1,
            state = Vector{Float32} => (ns,),
            action = Vector{Float32} => (na,),
        ),
    )

    stop_condition = StopAfterStep(trajectory_num+1, is_show_progress=!haskey(ENV, "CI"))
    hook = TotalRewardPerEpisode()
    Experiment(agent, env, stop_condition, hook, "# Collect $type Pendulum dataset generated by SAC")
end
