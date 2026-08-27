using Godot;
using System;
using System.Collections.Generic;

namespace Embervale.Feedback;

/// <summary>
/// Reference C# implementation for Embervale's camera and hit feedback director.
/// This file is intentionally not wired into the current GDScript project. It is
/// a drop-in design for a Godot C# branch or a future C# port of ImpactDirector.
/// </summary>
public partial class ImpactDirector : Node
{
    public enum FeedbackTier
    {
        Light,
        Medium,
        Heavy,
        Major,
        PerfectDodge
    }

    public sealed class FeedbackProfile
    {
        public readonly float ShakeAmplitude;
        public readonly float HitStopSeconds;
        public readonly float HitStopTimeScale;
        public readonly float Chroma;
        public readonly float FovPunch;
        public readonly int Priority;
        public readonly float Decay;

        public FeedbackProfile(float shakeAmplitude, float hitStopSeconds,
            float hitStopTimeScale, float chroma, float fovPunch,
            int priority, float decay)
        {
            ShakeAmplitude = shakeAmplitude;
            HitStopSeconds = hitStopSeconds;
            HitStopTimeScale = hitStopTimeScale;
            Chroma = chroma;
            FovPunch = fovPunch;
            Priority = priority;
            Decay = decay;
        }
    }

    private static readonly IReadOnlyDictionary<FeedbackTier, FeedbackProfile> Profiles =
        new Dictionary<FeedbackTier, FeedbackProfile>
        {
            // Shake is expressed in camera-local world units.
            [FeedbackTier.Light] = new(0.10f, 0.035f, 0.18f, 0.08f, 0.0f, 10, 12.0f),
            [FeedbackTier.Medium] = new(0.18f, 0.060f, 0.12f, 0.14f, 0.0f, 20, 10.0f),
            [FeedbackTier.Heavy] = new(0.32f, 0.100f, 0.08f, 0.24f, 1.5f, 30, 8.0f),
            [FeedbackTier.Major] = new(0.52f, 0.150f, 0.06f, 0.38f, 4.0f, 40, 6.0f),
            [FeedbackTier.PerfectDodge] = new(0.16f, 0.050f, 0.16f, 0.0f, 0.0f, 25, 11.0f),
        };

    [Export] public NodePath CameraPath { get; set; } = new("../Camera3D");
    [Export] public float GlobalAmplitudeCap { get; set; } = 0.65f;
    [Export] public float MobileAmplitudeMultiplier { get; set; } = 0.72f;
    [Export] public float ReducedMotionMultiplier { get; set; } = 0.35f;
    [Export] public bool MobileMode { get; set; }
    [Export] public bool ReducedMotion { get; set; }

    [Signal]
    public delegate void FeedbackTriggeredEventHandler(string tier, float shakeAmplitude,
        float hitStopSeconds, int priority);

    private Camera3D? _camera;
    private Vector3 _cameraBasePosition;
    private Vector3 _shakeVector = Vector3.Zero;
    private float _shakeEnvelope;
    private float _shakeDecay = 10.0f;
    private float _shakePhase;
    private int _activePriority;
    private double _hitStopUntil;
    private float _timeScaleBeforeHitStop = 1.0f;

    public override void _Ready()
    {
        _camera = GetNodeOrNull<Camera3D>(CameraPath);
        if (_camera != null)
            _cameraBasePosition = _camera.Position;
        SetProcess(true);
    }

    /// <summary>
    /// Queues one impact. Multiple requests are merged instead of adding
    /// unbounded camera offsets or repeatedly overwriting hit-stop state.
    /// </summary>
    public void RequestImpact(FeedbackTier tier,
        Vector3 worldDirection = default, float weight = 1.0f,
        int? priorityOverride = null)
    {
        if (!Profiles.TryGetValue(tier, out var profile))
            return;

        weight = Mathf.Clamp(weight, 0.0f, 1.5f);
        float qualityMultiplier = ReducedMotion
            ? ReducedMotionMultiplier
            : (MobileMode ? MobileAmplitudeMultiplier : 1.0f);
        float requestedAmplitude = profile.ShakeAmplitude * weight * qualityMultiplier;
        requestedAmplitude = Mathf.Clamp(requestedAmplitude, 0.0f, GlobalAmplitudeCap);

        int priority = priorityOverride ?? profile.Priority;
        bool hasActiveShake = _shakeEnvelope > 0.01f;
        float mergeWeight;

        if (hasActiveShake && priority < _activePriority)
        {
            // A weak event cannot interrupt a stronger event already on screen.
            mergeWeight = 0.25f;
        }
        else if (priority > _activePriority)
        {
            // A stronger event takes ownership but preserves some existing motion.
            mergeWeight = 0.85f;
            _activePriority = priority;
        }
        else
        {
            // Equal-priority events combine gently, avoiding machine-gun shaking.
            mergeWeight = 0.55f;
            _activePriority = priority;
        }

        _shakeEnvelope = Mathf.Min(
            GlobalAmplitudeCap,
            _shakeEnvelope + requestedAmplitude * mergeWeight);
        _shakeDecay = Mathf.Max(_shakeDecay, profile.Decay);

        Vector3 direction = worldDirection;
        if (direction.LengthSquared() < 0.0001f)
            direction = Vector3.Forward;
        direction = direction.Normalized();

        // 65% directional impulse + 35% deterministic transverse jitter.
        Vector3 transverse = new Vector3(
            Mathf.Sin(_shakePhase * 1.71f + 1.3f),
            Mathf.Cos(_shakePhase * 1.17f + 0.6f) * 0.45f,
            Mathf.Sin(_shakePhase * 0.83f + 2.4f));
        transverse = transverse.Normalized();
        Vector3 impulse = (direction * 0.65f + transverse * 0.35f).Normalized();
        _shakeVector = ClampLength(
            _shakeVector + impulse * requestedAmplitude,
            GlobalAmplitudeCap);

        ApplyHitStop(profile, qualityMultiplier, weight);
        EmitSignal(SignalName.FeedbackTriggered, tier.ToString(),
            requestedAmplitude, profile.HitStopSeconds, priority);
    }

    private void ApplyHitStop(FeedbackProfile profile,
        float qualityMultiplier, float weight)
    {
        float seconds = profile.HitStopSeconds * Mathf.Clamp(weight, 0.5f, 1.25f);
        if (ReducedMotion)
            seconds *= 0.75f;
        if (seconds <= 0.001f)
            return;

        double now = Time.GetTicksMsec() / 1000.0;
        double requestedUntil = now + seconds;
        if (_hitStopUntil <= now)
            _timeScaleBeforeHitStop = Engine.TimeScale;
        _hitStopUntil = Math.Max(_hitStopUntil, requestedUntil);

        // Never override a stronger pre-existing slow-motion effect.
        float requestedScale = Mathf.Clamp(profile.HitStopTimeScale, 0.05f, 1.0f);
        Engine.TimeScale = Mathf.Min(Engine.TimeScale, requestedScale);
    }

    public override void _Process(double delta)
    {
        _shakePhase += (float)delta;
        float dt = Mathf.Clamp((float)delta, 0.0f, 0.05f);

        if (_camera != null)
        {
            float envelopeDecay = Mathf.Exp(-_shakeDecay * dt);
            _shakeEnvelope *= envelopeDecay;
            _shakeVector = _shakeVector.Lerp(Vector3.Zero,
                1.0f - Mathf.Exp(-18.0f * dt));

            Vector3 noise = new Vector3(
                Mathf.Sin(_shakePhase * 31.0f),
                Mathf.Cos(_shakePhase * 37.0f) * 0.45f,
                Mathf.Sin(_shakePhase * 43.0f + 0.7f));
            Vector3 offset = _shakeVector + noise * (_shakeEnvelope * 0.35f);
            _camera.Position = _cameraBasePosition + ClampLength(offset, GlobalAmplitudeCap);

            if (_shakeEnvelope <= 0.005f)
            {
                _shakeEnvelope = 0.0f;
                _shakeVector = Vector3.Zero;
                _activePriority = 0;
            }
        }

        double now = Time.GetTicksMsec() / 1000.0;
        if (_hitStopUntil > 0.0 && now >= _hitStopUntil)
        {
            Engine.TimeScale = _timeScaleBeforeHitStop;
            _hitStopUntil = 0.0;
        }
    }

    public void SetCameraBasePosition(Vector3 position)
    {
        _cameraBasePosition = position;
    }

    public void ResetFeedback()
    {
        _shakeEnvelope = 0.0f;
        _shakeVector = Vector3.Zero;
        _activePriority = 0;
        if (_camera != null)
            _camera.Position = _cameraBasePosition;
        if (_hitStopUntil > 0.0)
            Engine.TimeScale = _timeScaleBeforeHitStop;
        _hitStopUntil = 0.0;
    }

    public static FeedbackProfile GetProfile(FeedbackTier tier) => Profiles[tier];

    private static Vector3 ClampLength(Vector3 value, float maxLength)
    {
        float length = value.Length();
        if (length <= maxLength || length <= 0.0001f)
            return value;
        return value / length * maxLength;
    }
}
