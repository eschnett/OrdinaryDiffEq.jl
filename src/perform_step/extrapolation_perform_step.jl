function initialize!(integrator,cache::RichardsonEulerCache)
  integrator.kshortsize = 2
  @unpack k,fsalfirst = cache
  integrator.fsalfirst = fsalfirst
  integrator.fsallast = k
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst,integrator.uprev,integrator.p,integrator.t) # For the interpolation, needs k at the updated point

  cache.step_no = 1
  cache.cur_order = max(integrator.alg.init_order, integrator.alg.min_order)
end

function perform_step!(integrator,cache::RichardsonEulerCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack k,fsalfirst,T,utilde,atmp,dtpropose,cur_order,A = cache

  @muladd @. u = uprev + dt*fsalfirst

  T[1,1] = copy(u)

  halfdt = dt/2
  for i in 2:size(T)[1]
    # Solve using Euler method
    @muladd @. u = uprev + halfdt*fsalfirst
    f(k, u, p, t+halfdt)
    for j in 2:2^(i-1)
      @muladd @. u = u + halfdt*k
      f(k, u, p, t+j*halfdt)
    end
    T[i,1] = copy(u)
    # Richardson Extrapolation
    for j in 2:i
      T[i,j] = ((2^(j-1))*T[i,j-1] - T[i-1,j-1])/((2^(j-1)) - 1)
    end

    halfdt = halfdt/2
  end

  if integrator.opts.adaptive
      minimum_work = Inf
      range_start = max(2,cur_order - 1)
      if cache.step_no == one(cache.step_no)
          range_start = 2
      end

      for i = range_start:min(size(T)[1], cur_order + 1)

          A = 2^(i-1)
          @. utilde = T[i,i] - T[i,i-1]
          atmp = calculate_residuals(utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
          EEst = integrator.opts.internalnorm(atmp)

          beta1 = integrator.opts.beta1
          e = integrator.EEst
          qold = integrator.qold

          integrator.opts.beta1 = 1/(i+1)
          integrator.EEst = EEst
          dtpropose = step_accept_controller!(integrator,integrator.alg,stepsize_controller!(integrator,integrator.alg))
          integrator.EEst = e
          integrator.opts.beta1 = beta1
          integrator.qold = qold

          work = A/dtpropose

          if work < minimum_work
              integrator.opts.beta1 = 1/(i+1)
              cache.dtpropose = dtpropose
              cache.cur_order = i
              minimum_work = work
              integrator.EEst = EEst
          end
      end
  end

  # using extrapolated value of u
  @. u = T[cache.cur_order, cache.cur_order]
  cache.step_no = cache.step_no + 1
  f(k, u, p, t+dt)
end

function initialize!(integrator,cache::RichardsonEulerConstantCache)
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  cache.step_no = 1
  cache.cur_order = max(integrator.alg.init_order, integrator.alg.min_order)
end

function perform_step!(integrator,cache::RichardsonEulerConstantCache,repeat_step=false)
  @unpack t,dt,uprev,f,p = integrator
  @unpack dtpropose, T, cur_order, work, A = cache
  @muladd u = @. uprev + dt*integrator.fsalfirst
  T[1,1] = u
  halfdt = dt/2
  for i in 2:min(size(T)[1], cur_order+1)
    # Solve using Euler method
    @muladd u = @. uprev + halfdt*integrator.fsalfirst
    k = f(u, p, t+halfdt)

    for j in 2:2^(i-1)
      @muladd u = @. u + halfdt*k
      k = f(u, p, t+j*halfdt)
    end
    T[i,1] = u

    # Richardson Extrapolation
    for j in 2:i
      T[i,j] = ((2^(j-1))*T[i,j-1] - T[i-1,j-1])/((2^(j-1)) - 1)
    end
    halfdt = halfdt/2
  end

  if integrator.opts.adaptive
      minimum_work = Inf
      range_start = max(2,cur_order - 1)
      if cache.step_no == one(cache.step_no)
          range_start = 2
      end

      for i = range_start:min(size(T)[1], cur_order + 1)

          A = 2^(i-1)
          utilde = T[i,i] - T[i,i-1]
          atmp = calculate_residuals(utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
          EEst = integrator.opts.internalnorm(atmp)

          beta1 = integrator.opts.beta1
          e = integrator.EEst
          qold = integrator.qold

          integrator.opts.beta1 = 1/(i+1)
          integrator.EEst = EEst
          dtpropose = step_accept_controller!(integrator,integrator.alg,stepsize_controller!(integrator,integrator.alg))
          integrator.EEst = e
          integrator.opts.beta1 = beta1
          integrator.qold = qold

          work = A/dtpropose

          if work < minimum_work
              integrator.opts.beta1 = 1/(i+1)
              cache.dtpropose = dtpropose
              cache.cur_order = i
              minimum_work = work
              integrator.EEst = EEst
          end
      end
  end

  cache.step_no = cache.step_no + 1
  integrator.u = T[cache.cur_order,cache.cur_order]

  k = f(integrator.u, p, t+dt)
  integrator.fsallast = k
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast

  # Use extrapolated value of u
end

function initialize!(integrator,cache::ExtrapolationMidpointDeuflhardCache)
  println("you are in initialize! of extrapolation acc. to Deuflhard and a mutable cache")
end

function initialize!(integrator,cache::ExtrapolationMidpointDeuflhardConstantCache)
  # begin copied from above:
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast # end copied from above
end

function perform_step!(integrator,cache::ExtrapolationMidpointDeuflhardConstantCache, repeat_step=false)
  @unpack t,dt,uprev,f,p = integrator
  @unpack dtpropose, Q, current_extrapolation_order = cache

  T = fill(zeros(eltype(uprev), size(uprev)), integrator.alg.max_extrapolation_order + 1) # storage for the internal discretisations obtained by the explicit midpoint rule
  utemp1 = utemp2 = similar(uprev) # auxiliary variable for computing the internal discretisations

  converged = false
  u = similar(uprev) # storage for the latest solution
  EEst = zero(eltype(Q)) # storage for the latest error estimate

  # set up order window
  n_win = max(integrator.alg.min_extrapolation_order, current_extrapolation_order - 1)
  N_win =  min(integrator.alg.max_extrapolation_order, current_extrapolation_order + 1)

  current_extrapolation_order = n_win # start with smalles order in the order window

  # compute internal discretisations
  for i = 0:current_extrapolation_order
    j_int = 2Int64(cache.subdividing_sequence[i+1])
    dt_int = dt/j_int # stepsize of the ith internal discretisation
    T[i+1] = uprev + dt_int*integrator.fsalfirst # Euler starting step
    utemp1 = uprev
    for j = 0:(j_int-2)
      utemp2 = T[i+1]
      T[i+1] = utemp1 + 2dt_int*f(T[i+1],p,(j+1)dt_int) # explicit midpoint rule
      utemp1 = utemp2
    end
  end

  # first verion for testing
  if !integrator.opts.adaptive
    integrator.u =  T[current_extrapolation_order]

    k = f(integrator.u, p, t+dt)
    integrator.fsallast = k
    integrator.k[1] = integrator.fsalfirst
    integrator.k[2] = integrator.fsallast
  end

end
