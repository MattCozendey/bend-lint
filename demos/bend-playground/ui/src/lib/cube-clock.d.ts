import type { CubesOutput, CubeFrame } from './types'
export interface CubeState extends CubeFrame { eventTime: number; index: number; sampled: boolean }
export function duration(data: CubesOutput): number
export function stateAt(data: CubesOutput, time: number): CubeState
export function nextTime(data: CubesOutput, time: number): number
