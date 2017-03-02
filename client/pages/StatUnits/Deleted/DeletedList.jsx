import React from 'react'

import ListItem from './ListItem'

class List extends React.Component {
  componentDidMount() {
    this.props.fetchData()
  }

  render() {
    return (
      <div>
        {this.props.isLoading
         ? 'loading...'
         : this.props.statUnits.map(x => <ListItem statUnit={x} restore={this.props.restore} />)}
      </div>
    )
  }
}

const { func, arrayOf, shape, bool, string, number } = React.PropTypes

List.propTypes = {
  fetchData: func.isRequired,
  isLoading: bool.isRequired,
  restore: func.isRequired,
  statUnits: arrayOf(shape({
    regId: number.isRequired,
    name: string.isRequired,
  })).isRequired,
}

export default List
