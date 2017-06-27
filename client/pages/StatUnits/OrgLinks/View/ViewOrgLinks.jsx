import React from 'react'
import { Segment } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'
import LinksTree from '../Components/LinksTree'

const { func, object } = React.PropTypes

class ViewOrgLinks extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    findUnit: func.isRequired,
    filter: object,
  }

  static defaultProps = {
    filter: undefined,
  }

  state = {
    fetechData: undefined,
  }

  componentDidMount() {
    const { filter } = this.props
    if (filter) this.searchUnit(filter)
  }

  searchUnit = (filter) => {
    this.setState({
      fetechData: () => this.props.findUnit(filter),
    }, () => {

    })
  }

  render() {
    const { localize, filter } = this.props
    const { fetechData } = this.state
    return (
      <div>
        <br />
        <Segment>
          <LinksTree localize={localize} getUnitsTree={fetechData} />
        </Segment>
      </div>
    )
  }
}

export default wrapper(ViewOrgLinks)
