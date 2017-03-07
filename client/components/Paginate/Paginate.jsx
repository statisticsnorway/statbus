import React from 'react'
import { Menu } from 'semantic-ui-react'
import { Link } from 'react-router'
import R from 'ramda'

import objectToQueryString from 'helpers/queryHelper'

const { func, node, number } = React.PropTypes

class Paginate extends React.Component {

  static propTypes = {
    children: node.isRequired,
    totalPages: number.isRequired,
    pageSize: number.isRequired,
    currentPage: number.isRequired,
    onChange: func.isRequired,
  }

  state = {
    query: '',
  }

  componentWillReceiveProps(nextProps) {
    const pick = R.pickAll(['totalPages', 'currentPage', 'pageSize'])
    const pagination = pick(this.props)
    const nextPagination = pick(nextProps)
    if (R.equals(nextPagination, pagination)) {
      this.setState({ query: objectToQueryString(nextPagination) })
    }
  }

  handleChange = (name, value) => () => {
    this.props.onChange({ [name]: value })
  }

  renderPageSizeLink = (size) => {
    const isActive = size !== this.props.pageSize
    const pathname = R.replace(`pageSize=${this.props.pageSize}`, `pageSize=${size}`, this.state.query)
    const link = isActive
      ? <Link to={pathname}>{size}</Link>
      : <b>{size}</b>
    return (
      <Menu.Item
        key={size}
        onClick={this.handleChange('pageSize', size)}
        content={size}
        disabled={size === this.props.pageSize}
        as={() => link}
      />
    )
  }

  renderPageLink = (page) => {
    const isActive = page !== this.props.currentPage
    const pathname = R.replace(`page=${this.props.currentPage}`, `page=${page}`, this.state.query)
    const link = isActive
      ? <Link to={pathname}>{page}</Link>
      : <b>{page}</b>
    return (
      <Menu.Item
        key={page}
        onClick={this.handleChange('currentPage', page)}
        content={page}
        disabled={!isActive}
        as={() => link}
      />
    )
  }

  render() {
    const { totalPages, children } = this.props
    const pageSizeLinks = [5, 10, 15, 25, 50].map(this.renderPageSizeLink)
    const pageLinks = R.range(1, totalPages).map(this.renderPageLink)

    return (
      <div>
        <Menu floated="right" pagination>
          {pageSizeLinks}
        </Menu>
        {...children}
        <Menu floated="center" pagination>
          {pageLinks}
        </Menu>
      </div>
    )
  }
}

export default Paginate
