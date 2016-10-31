import React from 'react'
import { connect } from 'react-redux'
import { bindActionCreators } from 'redux'
import { Button } from 'semantic-ui-react'
import Greeting from '../../components/Greeting'
import * as actions from './actions'

const Home = ({ value, add, increment, decrement }) => (
  <div>
    <Greeting />
    <br />
    <p>come on! try this counter</p>
    <span>{value}</span>
    <br />
    <Button onClick={decrement}>-</Button>
    <Button onClick={increment}>+</Button>
    <Button onClick={() => { add(5) }} primary>+5</Button>
  </div>
)

export default connect(
  ({ counter }) => ({ value: counter }),
  dispatch => bindActionCreators(actions, dispatch)
)(Home)
