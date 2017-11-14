import React from 'react'
import { node, number, func, oneOfType, shape, string } from 'prop-types'
import { Menu } from 'semantic-ui-react'
import { Link } from 'react-router'
import { is, replace } from 'ramda'

import { defaultPageSize, getPagesRange, getPageSizesRange } from 'helpers/paginate'
import styles from './styles.pcss'

class Paginate extends React.Component {
  static propTypes = {
    routing: shape({
      pathname: string,
      page: oneOfType([number, string]),
      pageSize: oneOfType([number, string]),
      queryString: string,
    }).isRequired,
    totalCount: oneOfType([number, string]),
    children: node.isRequired,
    localize: func.isRequired,
  }

  static defaultProps = {
    totalCount: 0,
  }

  getPage() {
    return Number(this.props.routing.page) || 1
  }

  getPageSize() {
    return Number(this.props.routing.pageSize) || defaultPageSize
  }

  getTotalCount() {
    return Number(this.props.totalCount)
  }

  getTotalPages() {
    return Math.ceil(this.getTotalCount() / this.getPageSize())
  }

  getLastPage() {
    return (this.getTotalPages() - 1) * this.getPageSize()
  }

  getDisplayTotalString() {
    const { localize } = this.props
    const to = this.getPage() * this.getPageSize()
    // eslint-disable-next-line no-mixed-operators
    const from = to - this.getPageSize() + 1

    const rangeDescription =
      this.getTotalPages() === 1
        ? localize('AllOf')
        : this.getTotalPages() === 0
          ? `0 ${localize('OfCount')}`
          : from === to
            ? `№ ${from} ${localize('OfCount')}`
            : to > this.getTotalCount()
              ? `${this.getLastPage() + 1} - ${this.getTotalCount()} ${localize('OfCount')}`
              : `${from} - ${to} ${localize('OfCount')}`

    return `${localize('Displaying')} ${rangeDescription} ${this.getTotalCount()}`
  }

  renderPageSizeLink(value) {
    const { pathname, queryString } = this.props.routing
    const current = this.getPageSize()

    const nextQueryString = queryString.includes(`pageSize=${current}`)
      ? replace(`pageSize=${current}`, `pageSize=${value}`, queryString)
      : queryString ? `${queryString}&pageSize=${value}` : `?pageSize=${value}`

    const isCurrent = value === current
    const link = () =>
      isCurrent ? (
        <b className="active item">{value}</b>
      ) : (
        <Link to={`${pathname}${nextQueryString}`} className="item">
          {value}
        </Link>
      )

    return <Menu.Item key={value} content={value} disabled={isCurrent} as={link} position="right" />
  }

  renderPageLink(value) {
    if (!is(Number, value)) return <Menu.Item key={value} content={value} disabled />

    const { pathname, queryString } = this.props.routing
    const current = this.getPage()

    const nextQueryString = queryString.includes(`page=${current}`)
      ? replace(`page=${current}`, `page=${value}`, queryString)
      : queryString ? `${queryString}&page=${value}` : `?page=${value}`

    const isCurrent = value === current
    const link = () =>
      isCurrent ? (
        <b className="active item">{value}</b>
      ) : (
        <Link to={`${pathname}${nextQueryString}`} className="item">
          {value}
        </Link>
      )

    return <Menu.Item key={value} content={value} disabled={isCurrent} as={link} />
  }

  render() {
    return (
      <div className={styles.root}>
        <Menu pagination fluid>
          <Menu.Item content={this.getDisplayTotalString()} />
          <Menu.Item content={`${this.props.localize('PageSize')}:`} position="right" />
          {getPageSizesRange(this.getPageSize()).map(x => this.renderPageSizeLink(x))}
        </Menu>
        {this.props.children}
        <Menu pagination fluid className={styles.footer}>
          <Menu.Item content={`${this.props.localize('PageNum')}:`} />
          {getPagesRange(this.getPage(), this.getTotalPages()).map(x => this.renderPageLink(x))}
        </Menu>
      </div>
    )
  }
}

export default Paginate
