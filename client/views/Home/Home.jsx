import React from 'react'
import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import Greeting from '../../components/Greeting'
import * as actions from './actions'

const Home = ({ value, add, increment, decrement }) => (
  <div>
    <Greeting />
    <br />
    <span>{value}</span>
    <br />
    <button onClick={decrement}>-</button>
    <button onClick={increment}>+</button>
    <button onClick={() => { add(5) }}>+5</button>
  </div>
)

export default connect(
  ({ counter }) => ({ value: counter }),
  dispatch => bindActionCreators(actions, dispatch)
)(Home)
